// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This library builds on Flutter's experimental windowing APIs. Those APIs
// are private and Flutter will make breaking changes to them, even in patch
// versions. As a result this package cannot be published to pub.dev and must
// be consumed as a path or git dependency on the Flutter `master` channel with
// `flutter config --enable-windowing`.
//
// See: https://github.com/flutter/flutter/issues/30701.

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: invalid_export_of_internal_element

import 'dart:ffi' as ffi;
import 'dart:ui' show Display, FlutterView;
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'src/gtk.dart';

// Re-export the SDK windowing pieces used to open windows dynamically. These are
// `@internal` in Flutter and therefore not reachable through the public
// `package:flutter/widgets.dart`, so consumers (e.g. the example app) get them
// from here instead.
export 'package:flutter/src/widgets/_window.dart'
    show
        WindowManager,
        WindowRegistry,
        WindowEntry,
        WindowScope,
        PopupWindowController,
        PopupWindowControllerDelegate;
export 'package:flutter/src/widgets/_window_positioner.dart'
    show
        WindowPositioner,
        WindowPositionerAnchor,
        WindowPositionerConstraintAdjustment;

/// The layer a shell surface is stacked on, from bottom to top.
typedef LayerShellLayer = GtkLayerShellLayer;

/// A screen edge a shell surface can be anchored to.
typedef LayerShellEdge = GtkLayerShellEdge;

/// How a shell surface interacts with keyboard input.
typedef LayerShellKeyboardMode = GtkLayerShellKeyboardMode;

const String _kWindowingDisabledErrorMessage = '''
Windowing APIs are not enabled.

Windowing APIs are currently experimental. Do not use windowing APIs in
production applications or plugins published to pub.dev.

To try experimental windowing APIs:
1. Switch to Flutter's main release channel.
2. Turn on the windowing feature flag.

See: https://github.com/flutter/flutter/issues/30701.
''';

bool _initialized = false;

/// Initializes layer-shell support and installs the windowing owner globally.
///
/// Call this once after `WidgetsFlutterBinding.ensureInitialized()` and before
/// creating any [LayershellWindowController].
void initLayerShell() {
  if (!isWindowingEnabled) {
    throw UnsupportedError(_kWindowingDisabledErrorMessage);
  }
  WidgetsBinding.instance.windowingOwner = ExtendedWindowingOwnerLinux();
  _initialized = true;
}

/// Returns the primary monitor's size in logical pixels.
Size getScreenSize() => GdkDisplay.getDefault().getMonitor(0).getGeometry();

/// Monitor information returned by [listMonitors].
class MonitorInfo {
  const MonitorInfo({
    required this.connector,
    required this.model,
    required this.manufacturer,
    required this.gdkMonitor,
    required this.position,
  });

  final String connector;
  final String model;
  final String manufacturer;
  final ffi.Pointer<ffi.NativeType> gdkMonitor;

  /// Top-left position of this monitor in logical pixels.
  final Offset position;

  @override
  String toString() =>
      'MonitorInfo(connector: $connector, model: $model, manufacturer: $manufacturer, position: $position)';
}

/// List all available monitors using GDK.
List<MonitorInfo> listMonitors() {
  final display = GdkDisplay.getDefault();
  final nMonitors = display.getNMonitors();
  final monitors = <MonitorInfo>[];

  for (var i = 0; i < nMonitors; i++) {
    final monitor = display.getMonitor(i);
    monitors.add(MonitorInfo(
      connector: monitor.getConnector(),
      model: monitor.getModel(),
      manufacturer: monitor.getManufacturer(),
      gdkMonitor: monitor.instance,
      position: monitor.getPosition(),
    ));
  }

  return monitors;
}

List<LayerShellEdge> anchorEdgesForPosition(String anchor) {
  switch (anchor) {
    case 'bottom':
      return [LayerShellEdge.bottom, LayerShellEdge.left, LayerShellEdge.right];
    case 'left':
      return [LayerShellEdge.left, LayerShellEdge.top, LayerShellEdge.bottom];
    case 'right':
      return [LayerShellEdge.right, LayerShellEdge.top, LayerShellEdge.bottom];
    default: // 'top'
      return [LayerShellEdge.top, LayerShellEdge.left, LayerShellEdge.right];
  }
}

LayerShellLayer layerFromString(String s) {
  switch (s) {
    case 'background':
      return LayerShellLayer.background;
    case 'bottom':
      return LayerShellLayer.bottom;
    case 'overlay':
      return LayerShellLayer.overlay;
    default: // 'top'
      return LayerShellLayer.top;
  }
}

/// A [WindowingOwnerLinux] that can also create gtk-layer-shell windows.
///
/// [initLayerShell] installs one of these as the global windowing owner. It
/// reuses the base owner's [LinuxWindowRegistrar] so that layer-shell windows are
/// registered alongside regular/dialog/popup windows and can be located by view
/// ID (for example when parenting a dialog or popup to a panel).
class ExtendedWindowingOwnerLinux extends WindowingOwnerLinux {
  /// Creates a layer-shell window controller and registers its native window
  /// and view with the owner's registrar.
  ///
  /// Mirrors how the base owner implements [createRegularWindowController].
  LayershellWindowController createLayerShellWindowController({
    LayerShellLayer layer = LayerShellLayer.top,
    List<LayerShellEdge> anchorEdges = const [
      LayerShellEdge.top,
      LayerShellEdge.left,
      LayerShellEdge.right,
    ],
    LayerShellKeyboardMode keyboardMode = LayerShellKeyboardMode.onDemand,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) {
    final controller = LayershellWindowController._internal(
      owner: this,
      layer: layer,
      anchorEdges: anchorEdges,
      keyboardMode: keyboardMode,
      width: width,
      height: height,
      exclusiveZone: exclusiveZone,
      monitor: monitor,
    );
    registrar.register(
      viewId: controller.rootView.viewId,
      windowHandle: controller._window.instance.cast(),
      viewHandle: controller._view.instance.cast(),
    );
    return controller;
  }

  /// Removes a layer-shell window from the registrar. Called by
  /// [LayershellWindowController.destroy]; routed through the owner because the
  /// [registrar] is only accessible from within a [WindowingOwnerLinux] subclass.
  void _unregisterLayerShellWindow(int viewId) => registrar.unregister(viewId);
}

class LayershellWindowController extends RegularWindowController
    implements WindowControllerLinux {
  /// Create a new LayershellWindowController.
  ///
  /// [initLayerShell] must have been called first. This delegates to
  /// [ExtendedWindowingOwnerLinux.createLayerShellWindowController] so the
  /// window is always registered with the system.
  factory LayershellWindowController({
    LayerShellLayer layer = LayerShellLayer.top,
    List<LayerShellEdge> anchorEdges = const [
      LayerShellEdge.top,
      LayerShellEdge.left,
      LayerShellEdge.right,
    ],
    LayerShellKeyboardMode keyboardMode = LayerShellKeyboardMode.onDemand,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }
    final owner = WidgetsBinding.instance.windowingOwner;
    if (!_initialized || owner is! ExtendedWindowingOwnerLinux) {
      throw StateError(
          'initLayerShell() must be called before creating a LayershellWindowController.');
    }
    return owner.createLayerShellWindowController(
      layer: layer,
      anchorEdges: anchorEdges,
      keyboardMode: keyboardMode,
      width: width,
      height: height,
      exclusiveZone: exclusiveZone,
      monitor: monitor,
    );
  }

  // Modelled on Flutter's RegularWindowControllerLinux, with the gtk-layer-shell
  // setup inserted *before* the window is realized. gtk_layer_init_for_window()
  // and every layer-shell property must be applied before realize()/present(),
  // which is why we drive window creation here rather than reusing the SDK's
  // regular controller (which realizes inside its own constructor).
  LayershellWindowController._internal({
    required ExtendedWindowingOwnerLinux owner,
    required LayerShellLayer layer,
    required List<LayerShellEdge> anchorEdges,
    required LayerShellKeyboardMode keyboardMode,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  })  : _owner = owner,
        _window = GtkWindow(GtkWindowType.toplevel),
        super.empty() {
    _windowMonitor = FlWindowMonitor(
      _window,
      onConfigure: notifyListeners,
      onStateChanged: notifyListeners,
      onIsActiveNotify: notifyListeners,
      onTitleNotify: notifyListeners,
      onClose: () {},
      onDestroy: () {
        _destroyed = true;
        notifyListeners();
      },
    );

    // gtk-layer-shell requires init *before* the window is realized/mapped, so
    // apply every layer-shell setting before realize().
    _window.layerInitForWindow();
    if (monitor != null && monitor.address != 0) {
      _window.layerSetMonitor(monitor);
    }
    if (exclusiveZone != null) {
      _window.layerAutoExclusiveZoneEnable();
      _window.layerSetExclusiveZone(exclusiveZone);
    }
    for (final edge in anchorEdges) {
      _window.layerSetAnchor(edge, true);
    }
    _window.layerSetLayer(layer);
    _window.layerSetKeyboardMode(keyboardMode);
    _window.setSizeRequest(width ?? -1, height ?? -1);
    _window.setDefaultSize(width ?? -1, height ?? -1);
    _window.setAppPaintable(true);
    // Force creation as Flutter will try and render to it immediately.
    _window.realize();

    final engine = FlEngine.current();
    _view = FlView(engine);
    _view.setBackgroundColor('#00000000');
    _viewMonitor = FlViewMonitor(
      _view,
      onFirstFrame: () {
        _window.present();
      },
    );
    final int viewId = _view.getId();
    rootView = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView view) => view.viewId == viewId,
    );
    _view.show();
    _window.add(_view);
  }

  final ExtendedWindowingOwnerLinux _owner;
  final GtkWindow _window;
  late final FlView _view;
  late final FlViewMonitor _viewMonitor;
  late final FlWindowMonitor _windowMonitor;
  bool _destroyed = false;

  @override
  Size get contentSize => _window.getSize();

  @override
  void destroy() {
    if (_destroyed) return;
    _viewMonitor.close();
    _viewMonitor.unref();
    _window.destroy();
    _windowMonitor.close();
    _windowMonitor.unref();
    _destroyed = true;
    _owner._unregisterLayerShellWindow(rootView.viewId);
  }

  @override
  bool get isActivated => _window.isActive();

  @override
  void setSize(Size size) =>
      _window.resize(size.width.toInt(), size.height.toInt());

  @override
  void activate() => _window.present();

  @override
  bool get isDestroyed => _destroyed;

  @override
  ffi.Pointer<ffi.Void> get windowHandle {
    if (_destroyed) {
      throw StateError('Window has been destroyed.');
    }
    return _window.instance.cast();
  }

  @override
  ffi.Pointer<ffi.Void> get flutterViewHandle {
    if (_destroyed) {
      throw StateError('Window has been destroyed.');
    }
    return _view.instance.cast();
  }

  // Layer-shell windows are compositor-managed — no-op these operations.

  @override
  bool get isFullscreen => false;

  @override
  bool get isMaximized => false;

  @override
  bool get isMinimized => false;

  @override
  void setConstraints(BoxConstraints constraints) {}

  @override
  void setFullscreen(bool fullscreen, {Display? display}) {}

  @override
  void setMaximized(bool maximized) {}

  @override
  void setMinimized(bool minimized) {}

  @override
  void setTitle(String title) {}

  @override
  String get title => '';
}

class LayerShellWindow extends StatelessWidget {
  LayerShellWindow({super.key, required this.controller, required this.child}) {
    if (!isWindowingEnabled) {
      throw UnsupportedError(_kWindowingDisabledErrorMessage);
    }
  }

  final LayershellWindowController controller;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => View(
        view: controller.rootView,
        child: WindowScope(controller: controller, child: child),
      ),
    );
  }
}
