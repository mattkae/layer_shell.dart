// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Stopgaps for two defects in Flutter's Linux embedder that freeze every
// window of a multi-window app on Wayland. Neither is specific to layer-shell:
// they affect any view the engine creates after the first, including the SDK's
// own popups, tooltips and dialogs. They live here because a desktop shell is
// where they bite hardest - many surfaces, popups opening while others animate.
//
// Both are installed by `initLayerShell()` and both are meant to be deleted
// once the embedder is fixed; see the README's "Engine workarounds" section.

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:flutter/scheduler.dart';

import 'gtk.dart';

bool _installed = false;

/// Installs the workarounds. Safe to call more than once; only the first call
/// has any effect.
void installEngineWorkarounds({
  bool contextRelease = true,
  bool stallWatchdog = true,
}) {
  if (_installed) {
    return;
  }
  _installed = true;
  // Both defects are in the Wayland subsurface renderer. On X11 the engine
  // renders through GdkGLContext and neither applies.
  if (!_defaultDisplayIsWayland()) {
    return;
  }
  if (contextRelease) {
    _installContextReleaseHook();
  }
  if (stallWatchdog) {
    _RenderStallWatchdog.instance.start();
  }
}

// ---------------------------------------------------------------------------
// 1. The engine's render context is left current on the platform thread.
//
// Realizing a view runs fl_compositor_opengl_new() on the platform thread,
// which makes the engine's *render* context current there to probe for
// glBlitFramebuffer and never releases it. The raster thread normally owns
// that context, so eglMakeCurrent() fails with EGL_BAD_ACCESS and nothing
// happens. But while the raster thread is presenting a frame it has switched
// to the subsurface's own context, and for that long the render context is up
// for grabs: a view realized in that window takes it, and from then on every
// frame fails with
//
//   Could not make the context current to acquire the frame.
//
// until something else on the platform thread happens to change context.
//
// A GObject emission hook runs straight after a signal's class handler, which
// for GtkWidget::realize is where the context was taken. So hook realize and
// give the context back.
// ---------------------------------------------------------------------------

typedef _EmissionHookC = ffi.Int Function(
    ffi.Pointer<ffi.Void> hint,
    ffi.UnsignedInt nParamValues,
    ffi.Pointer<ffi.Void> paramValues,
    ffi.Pointer<ffi.Void> data);

// Kept alive for the life of the process: the hook is never removed.
ffi.NativeCallable<_EmissionHookC>? _realizeHook;

void _installContextReleaseHook() {
  final _Egl? egl = _Egl.load();
  if (egl == null) {
    return;
  }
  final ffi.Pointer<ffi.Uint8> name = stringToNative('realize');
  final int signalId = _gSignalLookup(name, _gtkWidgetGetType());
  gFree(name);
  if (signalId == 0) {
    return;
  }
  _realizeHook = ffi.NativeCallable<_EmissionHookC>.isolateLocal(
    (ffi.Pointer<ffi.Void> hint, int nParamValues,
        ffi.Pointer<ffi.Void> paramValues, ffi.Pointer<ffi.Void> data) {
      // The first parameter of every emission is the instance.
      if (nParamValues > 0 && _isFlutterWidget(_gValueGetObject(paramValues))) {
        if (egl.releaseCurrentContext()) {
          // A frame rasterized while the context was away has been dropped.
          SchedulerBinding.instance.scheduleFrame();
        }
      }
      return 1; // Stay connected.
    },
    exceptionalReturn: 1,
  );
  _gSignalAddEmissionHook(
      signalId, 0, _realizeHook!.nativeFunction, ffi.nullptr, ffi.nullptr);
}

/// Whether [instance] is one of the embedder's widgets (FlView and the
/// FlViewRenderer subclasses it realizes).
bool _isFlutterWidget(ffi.Pointer<ffi.Void> instance) {
  if (instance == ffi.nullptr) {
    return false;
  }
  final ffi.Pointer<ffi.Uint8> name = _gTypeNameFromInstance(instance);
  // 'F', 'l', then an upper-case letter.
  return name != ffi.nullptr &&
      name[0] == 0x46 &&
      name[1] == 0x6c &&
      name[2] >= 0x41 &&
      name[2] <= 0x5a;
}

class _Egl {
  _Egl._(this._getCurrentContext, this._getCurrentDisplay, this._makeCurrent);

  /// Null when libEGL is not there to be loaded, in which case the engine is
  /// not rendering with it either.
  static _Egl? load() {
    try {
      final ffi.DynamicLibrary lib = ffi.DynamicLibrary.open('libEGL.so.1');
      return _Egl._(
        lib.lookupFunction<ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()>('eglGetCurrentContext'),
        lib.lookupFunction<ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()>('eglGetCurrentDisplay'),
        lib.lookupFunction<
            ffi.UnsignedInt Function(ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('eglMakeCurrent'),
      );
    } on ArgumentError {
      return null;
    }
  }

  final ffi.Pointer<ffi.Void> Function() _getCurrentContext;
  final ffi.Pointer<ffi.Void> Function() _getCurrentDisplay;
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) _makeCurrent;

  /// Leaves the calling thread with no current context. Returns whether it
  /// had one.
  ///
  /// The embedder makes a context current on the platform thread each time it
  /// needs one there, and clears it itself after realizing the implicit view,
  /// so nothing on this thread depends on one staying current.
  bool releaseCurrentContext() {
    if (_getCurrentContext() == ffi.nullptr) {
      return false;
    }
    // EGL_NO_SURFACE and EGL_NO_CONTEXT are both null handles.
    _makeCurrent(_getCurrentDisplay(), ffi.nullptr, ffi.nullptr, ffi.nullptr);
    return true;
  }
}

// ---------------------------------------------------------------------------
// 2. The raster thread waits forever for a buffer.
//
// A view sized to its content - every popup and tooltip - keeps its Wayland
// subsurface *synchronized*, and any other view's is synchronized for the
// length of a resize. A frame committed to a synchronized subsurface takes
// effect only when GTK next commits the parent surface, and until then the
// compositor holds on to its buffer. The raster thread presents regardless, so
// when GTK is not committing - its frame clock is waiting on a frame callback,
// or nothing asked it to redraw - Mesa runs out of buffers and eglSwapBuffers()
// blocks until a commit that is not coming. There is one raster thread, so
// every window stops, with nothing in the log.
//
// Mir makes this far easier to reach: it never releases a buffer that was
// replaced in a synchronized subsurface's cache, so each such frame costs the
// surface one of its four buffers for good.
//
// The platform thread is not blocked while this happens. So notice that frames
// have stopped arriving and commit the parent surfaces, which is the event the
// raster thread is waiting for.
// ---------------------------------------------------------------------------

class _RenderStallWatchdog {
  _RenderStallWatchdog._();

  static final _RenderStallWatchdog instance = _RenderStallWatchdog._();

  /// How often to look for a stall.
  static const Duration _period = Duration(milliseconds: 250);

  /// A frame that was asked for and has not begun after this long is stuck:
  /// the engine starts one within a vsync interval unless the raster thread
  /// has stopped taking them.
  static const Duration _beginFrameGrace = Duration(milliseconds: 200);

  /// The engine reports rasterized frames in batches up to a second apart in
  /// release builds, so allow for that before concluding one never finished.
  static const Duration _rasterGrace = Duration(milliseconds: 1500);

  /// How often to commit while [_assisting].
  static const Duration _assistPeriod = Duration(milliseconds: 16);

  final Stopwatch _clock = Stopwatch();
  Duration _lastFrameBegan = Duration.zero;
  Duration _lastRasterReport = Duration.zero;
  int _built = 0;
  int _rasterized = 0;

  // A stall is a property of a window - its buffers are gone, or its frame
  // clock is stopped - so one is followed by another for as long as that
  // window lives, and finding each takes [_beginFrameGrace]. After the first,
  // stop waiting to be asked: commit after every frame until the set of
  // windows changes. Only frames cost anything, so an idle shell stays idle.
  Timer? _assistTimer;
  int _assistedToplevels = 0;
  int _builtAtLastCommit = 0;

  bool get _assisting => _assistTimer != null;

  void start() {
    if (_clock.isRunning) {
      return;
    }
    _clock.start();
    final SchedulerBinding scheduler = SchedulerBinding.instance;
    scheduler.addPersistentFrameCallback((Duration _) {
      _built++;
      _lastFrameBegan = _clock.elapsed;
    });
    scheduler.addTimingsCallback((List<FrameTiming> timings) {
      _rasterized += timings.length;
      _lastRasterReport = _clock.elapsed;
    });
    Timer.periodic(_period, (Timer _) => _check());
  }

  void _check() {
    if (_assisting) {
      return;
    }
    final Duration now = _clock.elapsed;
    final bool frameNotBeginning =
        SchedulerBinding.instance.hasScheduledFrame &&
            now - _lastFrameBegan > _beginFrameGrace;
    final bool frameNotFinishing = _built > _rasterized &&
        now - _lastFrameBegan > _rasterGrace &&
        now - _lastRasterReport > _rasterGrace;
    if (!frameNotBeginning && !frameNotFinishing) {
      return;
    }
    // Frames the engine skipped are never reported, so resynchronise rather
    // than find the same shortfall again.
    _rasterized = _built;
    _assistedToplevels = _commitToplevelSurfaces();
    _builtAtLastCommit = _built;
    _assistTimer = Timer.periodic(_assistPeriod, (Timer _) => _assist());
  }

  void _assist() {
    if (_built == _builtAtLastCommit &&
        !SchedulerBinding.instance.hasScheduledFrame) {
      return; // Nothing has been drawn and nothing is waiting to be.
    }
    _builtAtLastCommit = _built;
    if (_commitToplevelSurfaces() != _assistedToplevels) {
      // A window opened or closed. If the one that stalled is still here the
      // next stall brings this back.
      _assistTimer!.cancel();
      _assistTimer = null;
    }
  }
}

/// Sends a bare `wl_surface.commit` for every realized top-level window, and
/// returns a value that changes when the set of those windows does.
///
/// With no buffer attached this changes nothing about the window itself; its
/// effect is to apply whatever its synchronized subsurfaces have cached.
int _commitToplevelSurfaces() {
  int identity = 0;
  final ffi.Pointer<_GList> toplevels = _gtkWindowListToplevels();
  for (ffi.Pointer<_GList> link = toplevels;
      link != ffi.nullptr;
      link = link.ref.next) {
    final ffi.Pointer<ffi.Void> gdkWindow = _gtkWidgetGetWindow(link.ref.data);
    if (gdkWindow == ffi.nullptr) {
      continue; // Not realized.
    }
    final ffi.Pointer<ffi.Void> surface = _gdkWaylandWindowGetWlSurface(gdkWindow);
    if (surface != ffi.nullptr) {
      identity = Object.hash(identity, surface.address);
      // wl_surface.commit takes no arguments; libwayland still wants a
      // non-null array.
      _wlProxyMarshalArray(surface, _kWlSurfaceCommit, _noArguments);
    }
  }
  _gListFree(toplevels);
  return identity;
}

/// Opcode of `wl_surface.commit` in the core protocol.
const int _kWlSurfaceCommit = 6;

final ffi.Pointer<ffi.Void> _noArguments = gMalloc0(16).cast<ffi.Void>();

bool _defaultDisplayIsWayland() {
  final ffi.Pointer<ffi.Void> display = _gdkDisplayGetDefault();
  return display != ffi.nullptr &&
      _gTypeCheckInstanceIsA(display, _gdkWaylandDisplayGetType()) != 0;
}

final class _GList extends ffi.Struct {
  external ffi.Pointer<ffi.Void> data;
  external ffi.Pointer<_GList> next;
  external ffi.Pointer<_GList> prev;
}

@ffi.Native<ffi.UnsignedInt Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
    symbol: 'g_signal_lookup')
external int _gSignalLookup(ffi.Pointer<ffi.Uint8> name, int type);

@ffi.Native<ffi.Size Function()>(symbol: 'gtk_widget_get_type')
external int _gtkWidgetGetType();

@ffi.Native<
    ffi.UnsignedLong Function(
        ffi.UnsignedInt,
        ffi.Uint32,
        ffi.Pointer<ffi.NativeFunction<_EmissionHookC>>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>)>(symbol: 'g_signal_add_emission_hook')
external int _gSignalAddEmissionHook(
    int signalId,
    int detail,
    ffi.Pointer<ffi.NativeFunction<_EmissionHookC>> hook,
    ffi.Pointer<ffi.Void> data,
    ffi.Pointer<ffi.Void> destroy);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
    symbol: 'g_value_get_object')
external ffi.Pointer<ffi.Void> _gValueGetObject(ffi.Pointer<ffi.Void> value);

@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>)>(
    symbol: 'g_type_name_from_instance')
external ffi.Pointer<ffi.Uint8> _gTypeNameFromInstance(
    ffi.Pointer<ffi.Void> instance);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Size)>(
    symbol: 'g_type_check_instance_is_a')
external int _gTypeCheckInstanceIsA(ffi.Pointer<ffi.Void> instance, int type);

@ffi.Native<ffi.Pointer<ffi.Void> Function()>(symbol: 'gdk_display_get_default')
external ffi.Pointer<ffi.Void> _gdkDisplayGetDefault();

@ffi.Native<ffi.Size Function()>(symbol: 'gdk_wayland_display_get_type')
external int _gdkWaylandDisplayGetType();

@ffi.Native<ffi.Pointer<_GList> Function()>(symbol: 'gtk_window_list_toplevels')
external ffi.Pointer<_GList> _gtkWindowListToplevels();

@ffi.Native<ffi.Void Function(ffi.Pointer<_GList>)>(symbol: 'g_list_free')
external void _gListFree(ffi.Pointer<_GList> list);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
    symbol: 'gtk_widget_get_window')
external ffi.Pointer<ffi.Void> _gtkWidgetGetWindow(ffi.Pointer<ffi.Void> widget);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
    symbol: 'gdk_wayland_window_get_wl_surface')
external ffi.Pointer<ffi.Void> _gdkWaylandWindowGetWlSurface(
    ffi.Pointer<ffi.Void> window);

@ffi.Native<
    ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Uint32,
        ffi.Pointer<ffi.Void>)>(symbol: 'wl_proxy_marshal_array')
external void _wlProxyMarshalArray(
    ffi.Pointer<ffi.Void> proxy, int opcode, ffi.Pointer<ffi.Void> args);
