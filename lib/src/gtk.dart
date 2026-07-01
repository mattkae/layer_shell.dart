// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;
import 'package:flutter/src/widgets/binding.dart';

// Load the GTK Layer Shell library
final ffi.DynamicLibrary gtkLayerShell = () {
  try {
    // Try to open the library from the system
    return ffi.DynamicLibrary.open('libgtk-layer-shell.so.0');
  } catch (e) {
    // Fallback: try without version suffix
    try {
      return ffi.DynamicLibrary.open('libgtk-layer-shell.so');
    } catch (e) {
      // Last resort: use the process itself (symbols should be available via linking)
      return ffi.DynamicLibrary.process();
    }
  }
}();

// TODO: The beginning of this file (minus the GTK layer shell specific code)
// is taken directly from the Linux windowing implementation in Flutter. Once
// that code is made public we should remove the duplicated code.

// Maximum width and height a window can be.
// In C this would be INT_MAX, but since we can't determine that from Dart let's assume it's 32 bit signed. In any case this is far beyond any reasonable window size.
const int _kMaxWindowDimensions = 0x7fffffff;

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Int)>(symbol: 'g_malloc0')
external ffi.Pointer<ffi.NativeType> gMalloc0(int count);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(symbol: 'g_free')
external void gFree(ffi.Pointer<ffi.NativeType> value);

ffi.Pointer<ffi.Uint8> stringToNative(String value) {
  final Uint8List units = utf8.encode(value);
  final ffi.Pointer<ffi.Uint8> buffer =
      gMalloc0(units.length + 1).cast<ffi.Uint8>();
  final Uint8List nativeString = buffer.asTypedList(units.length + 1);
  nativeString.setAll(0, units);
  nativeString[units.length] = 0;
  return buffer;
}

String nativeToString(ffi.Pointer<ffi.Uint8> value) {
  var length = 0;
  while (value[length] != 0) {
    length++;
  }
  return utf8.decode(value.asTypedList(length));
}

/// Wraps GObject
class GObject {
  const GObject(this.instance);

  final ffi.Pointer<ffi.NativeType> instance;

  /// Drop reference to this object.
  void unref() {
    _unref(instance);
  }

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'g_object_unref')
  external static void _unref(ffi.Pointer<ffi.NativeType> widget);
}

/// Wraps GtkContainer
class GtkContainer extends GtkWidget {
  const GtkContainer(super.instance);

  /// Adds [child] widget to this container.
  void add(GtkWidget child) {
    _gtkContainerAdd(instance, child.instance);
  }

  @ffi.Native<
      ffi.Void Function(
          ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gtk_container_add',
  )
  external static void _gtkContainerAdd(
    ffi.Pointer<ffi.NativeType> container,
    ffi.Pointer<ffi.NativeType> child,
  );
}

/// Wraps GtkWidget
class GtkWidget extends GObject {
  const GtkWidget(super.instance);

  /// Show the widget (defaults to hidden).
  void show() {
    _gtkWidgetShow(instance);
  }

  /// Get the low level window backing this widget.
  GdkWindow getWindow() {
    return GdkWindow(_gtkWidgetGetWindow(instance));
  }

  /// Destroy the widget.
  void destroy() {
    _gtkWindowDestroy(instance);
  }

  void setSizeRequest(int width, int height) {
    _gtkWidgetSetSizeRequest(instance, width, height);
  }

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_widget_show')
  external static void _gtkWidgetShow(ffi.Pointer<ffi.NativeType> widget);

  @ffi.Native<
      ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gtk_widget_get_window',
  )
  external static ffi.Pointer<ffi.NativeType> _gtkWidgetGetWindow(
    ffi.Pointer<ffi.NativeType> widget,
  );

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_widget_destroy')
  external static void _gtkWindowDestroy(ffi.Pointer<ffi.NativeType> widget);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int, ffi.Int)>(
    symbol: 'gtk_widget_set_size_request',
  )
  external static void _gtkWidgetSetSizeRequest(
    ffi.Pointer<ffi.NativeType> window,
    int width,
    int height,
  );
}

/// Wraps GdkWindow
class GdkWindow extends GObject {
  const GdkWindow(super.instance);

  /// Gets the window state bitfield (_GDK_WINDOW_STATE_*).
  int getState() {
    return _gdkWindowGetState(instance);
  }

  @ffi.Native<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gdk_window_get_state')
  external static int _gdkWindowGetState(ffi.Pointer<ffi.NativeType> window);
}

/// Wraps GdkDisplay
class GdkDisplay extends GObject {
  const GdkDisplay(super.instance);

  /// Get the default display.
  static GdkDisplay getDefault() {
    return GdkDisplay(_gdkDisplayGetDefault());
  }

  /// Get the number of monitors for this display.
  int getNMonitors() {
    return _gdkDisplayGetNMonitors(instance);
  }

  /// Get the monitor at the specified index.
  GdkMonitor getMonitor(int index) {
    return GdkMonitor(_gdkDisplayGetMonitor(instance, index));
  }

  @ffi.Native<ffi.Pointer<ffi.NativeType> Function()>(
      symbol: 'gdk_display_get_default')
  external static ffi.Pointer<ffi.NativeType> _gdkDisplayGetDefault();

  @ffi.Native<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gdk_display_get_n_monitors')
  external static int _gdkDisplayGetNMonitors(
      ffi.Pointer<ffi.NativeType> display);

  @ffi.Native<
      ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>,
          ffi.Int)>(symbol: 'gdk_display_get_monitor')
  external static ffi.Pointer<ffi.NativeType> _gdkDisplayGetMonitor(
      ffi.Pointer<ffi.NativeType> display, int monitorNum);
}

/// Wraps GdkMonitor
class GdkMonitor extends GObject {
  const GdkMonitor(super.instance);

  /// Get the model name of the monitor.
  String getModel() {
    try {
      final ptr = _gdkMonitorGetModel(instance);
      return ptr.address == 0 ? '' : nativeToString(ptr);
    } catch (e) {
      return '';
    }
  }

  /// Get the connector name of the monitor (GDK 3.22+).
  String getConnector() {
    try {
      final lookup = ffi.DynamicLibrary.process().lookup<
          ffi.NativeFunction<
              ffi.Pointer<ffi.Uint8> Function(
                  ffi.Pointer<ffi.NativeType>)>>('gdk_monitor_get_connector');
      final func = lookup.asFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>();
      final ptr = func(instance);
      return ptr.address == 0 ? '' : nativeToString(ptr);
    } catch (e) {
      return '';
    }
  }

  /// Get the manufacturer name of the monitor.
  String getManufacturer() {
    try {
      final ptr = _gdkMonitorGetManufacturer(instance);
      return ptr.address == 0 ? '' : nativeToString(ptr);
    } catch (e) {
      return '';
    }
  }

  @ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gdk_monitor_get_model')
  external static ffi.Pointer<ffi.Uint8> _gdkMonitorGetModel(
      ffi.Pointer<ffi.NativeType> monitor);

  @ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gdk_monitor_get_manufacturer')
  external static ffi.Pointer<ffi.Uint8> _gdkMonitorGetManufacturer(
      ffi.Pointer<ffi.NativeType> monitor);

  /// Get the monitor geometry (position and size) in logical pixels.
  Size getGeometry() {
    final ptr = gMalloc0(16).cast<GdkRectangle>(); // 4 × int32
    _gdkMonitorGetGeometry(instance, ptr);
    final w = ptr.ref.width.toDouble();
    final h = ptr.ref.height.toDouble();
    gFree(ptr.cast());
    return Size(w, h);
  }

  /// Get the monitor's top-left position in logical pixels.
  Offset getPosition() {
    final ptr = gMalloc0(16).cast<GdkRectangle>(); // 4 × int32
    _gdkMonitorGetGeometry(instance, ptr);
    final x = ptr.ref.x.toDouble();
    final y = ptr.ref.y.toDouble();
    gFree(ptr.cast());
    return Offset(x, y);
  }

  @ffi.Native<
      ffi.Void Function(ffi.Pointer<ffi.NativeType>,
          ffi.Pointer<GdkRectangle>)>(symbol: 'gdk_monitor_get_geometry')
  external static void _gdkMonitorGetGeometry(
      ffi.Pointer<ffi.NativeType> monitor, ffi.Pointer<GdkRectangle> geometry);
}

/// A GdkRectangle: position and size in integer logical pixels.
final class GdkRectangle extends ffi.Struct {
  @ffi.Int()
  external int x;
  @ffi.Int()
  external int y;
  @ffi.Int()
  external int width;
  @ffi.Int()
  external int height;
}

/// Wraps GdkGeometry
final class GdkGeometry extends ffi.Struct {
  factory GdkGeometry() {
    return ffi.Struct.create();
  }

  @ffi.Int()
  external int minWidth;

  @ffi.Int()
  external int minHeight;

  @ffi.Int()
  external int maxWidth;

  @ffi.Int()
  external int maxHeight;

  @ffi.Int()
  external int baseWidth;

  @ffi.Int()
  external int baseHeight;

  @ffi.Int()
  external int widthInc;

  @ffi.Int()
  external int heightInc;

  @ffi.Double()
  external double minAspect;

  @ffi.Double()
  external double maxAspect;

  @ffi.Int()
  external int winGravity;
}

/// Wraps GdkRGBA
final class GdkRGBA extends ffi.Struct {
  factory GdkRGBA() {
    return ffi.Struct.create();
  }

  @ffi.Double()
  external double red;

  @ffi.Double()
  external double green;

  @ffi.Double()
  external double blue;

  @ffi.Double()
  external double alpha;
}

// GTK Layer Shell enums

/// GtkLayerShellLayer - Stacking layers for layer shell surfaces.
///
/// These values indicate which layer a surface is in. Higher layers are drawn
/// above lower layers.
enum GtkLayerShellLayer {
  /// The background layer.
  background(0),

  /// The bottom layer.
  bottom(1),

  /// The top layer.
  top(2),

  /// The overlay layer.
  overlay(3);

  const GtkLayerShellLayer(this.value);
  final int value;
}

/// GtkLayerShellEdge - Edges of the screen.
///
/// Used to specify which edge(s) of the screen a surface should be anchored to
/// or have margins/exclusive zones on.
enum GtkLayerShellEdge {
  /// The left edge of the screen.
  left(0),

  /// The right edge of the screen.
  right(1),

  /// The top edge of the screen.
  top(2),

  /// The bottom edge of the screen.
  bottom(3);

  const GtkLayerShellEdge(this.value);
  final int value;
}

/// GtkLayerShellKeyboardMode - How keyboard events are handled.
///
/// Determines whether and how a layer surface receives keyboard input.
enum GtkLayerShellKeyboardMode {
  /// This window should not receive keyboard events.
  none(0),

  /// This window should have exclusive focus if it is on the top or overlay layer.
  exclusive(1),

  /// The user should be able to focus and unfocus this window (requires protocol version 4+).
  onDemand(2);

  const GtkLayerShellKeyboardMode(this.value);
  final int value;
}

/// Wraps GtkWindow
class GtkWindow extends GtkContainer {
  /// Create a new GtkWindow
  GtkWindow(super.instance);

  /// Make window visible and grab focus.
  void present() {
    _gtkWindowPresent(instance);
  }

  /// Sets the parent window.
  void setTransientFor(GtkWindow parent) {
    _gtkWindowSetTransientFor(instance, parent.instance);
  }

  /// Set if this window is modal to its parent.
  void setModal(bool modal) {
    _gtkWindowSetModal(instance, modal);
  }

  /// Set the type of this window.
  void setTypeHint(int hint) {
    _gtkWindowSetTypeHint(instance, hint);
  }

  /// Sets the title of the window.
  void setTitle(String title) {
    final ffi.Pointer<ffi.Uint8> titleBuffer = stringToNative(title);
    _gtkWindowSetTitle(instance, titleBuffer);
    gFree(titleBuffer);
  }

  /// Gets the current title of the window.
  String getTitle() {
    return nativeToString(_gtkWindowGetTitle(instance));
  }

  /// Set the default size of the window.
  void setDefaultSize(int width, int height) {
    _gtkWindowSetDefaultSize(instance, width, height);
  }

  /// Set minimum and maximum size of the window.
  void setGeometryHints(
      {int? minWidth, int? minHeight, int? maxWidth, int? maxHeight}) {
    final ffi.Pointer<GdkGeometry> geometry = gMalloc0(
      ffi.sizeOf<GdkGeometry>(),
    ).cast<GdkGeometry>();
    final GdkGeometry g = geometry.ref;
    var geometryMask = 0;
    if (minWidth != null || minHeight != null) {
      g.minWidth = minWidth ?? 0;
      g.minHeight = minHeight ?? 0;
      geometryMask |= 2; // GDK_HINT_MIN_SIZE
    }
    if (maxWidth != null || maxHeight != null) {
      g.maxWidth = maxWidth ?? _kMaxWindowDimensions;
      g.maxHeight = maxHeight ?? _kMaxWindowDimensions;
      geometryMask |= 4; // GDK_HINT_MAX_SIZE
    }
    _gtkWindowSetGeometryHints(instance, ffi.nullptr, geometry, geometryMask);
    gFree(geometry);
  }

  /// Resize to [width]x[height].
  void resize(int width, int height) {
    _gtkWindowResize(instance, width, height);
  }

  /// Move the window to ([x], [y]) in screen coordinates.
  void move(int x, int y) {
    _gtkWindowMove(instance, x, y);
  }

  /// Maximize window.
  void maximize() {
    _gtkWindowMaximize(instance);
  }

  /// Unaximize window.
  void unmaximize() {
    _gtkWindowUnmaximize(instance);
  }

  /// Iconify (minimize) window.
  void iconify() {
    _gtkWindowIconify(instance);
  }

  /// Deconify (unminimize) window.
  void deiconify() {
    _gtkWindowDeiconify(instance);
  }

  /// Make window fullscreen.
  void fullscreen() {
    _gtkWindowFullscreen(instance);
  }

  /// Leave fullscreen.
  void unfullscreen() {
    _gtkWindowUnfullscreen(instance);
  }

  /// Get the current size of the window.
  Size getSize() {
    final ffi.Pointer<ffi.Int> width =
        gMalloc0(ffi.sizeOf<ffi.Int>()).cast<ffi.Int>();
    final ffi.Pointer<ffi.Int> height =
        gMalloc0(ffi.sizeOf<ffi.Int>()).cast<ffi.Int>();
    _gtkWindowGetSize(instance, width, height);
    final result = Size(width.value.toDouble(), height.value.toDouble());
    gFree(width);
    gFree(height);
    return result;
  }

  /// true if this window has keyboard focus.
  bool isActive() {
    return _gtkWindowIsActive(instance);
  }

  void setAppPaintable(bool appPaintable) {
    _gtkWidgetSetAppPaintable(instance, appPaintable);
  }

  @ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Int)>(
      symbol: 'gtk_window_new')
  external static ffi.Pointer<ffi.NativeType> gtkWindowNew(int type);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_present')
  external static void _gtkWindowPresent(ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Bool)>(
    symbol: 'gtk_window_set_modal',
  )
  external static void _gtkWindowSetModal(
      ffi.Pointer<ffi.NativeType> window, bool modal);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int)>(
    symbol: 'gtk_window_set_type_hint',
  )
  external static void _gtkWindowSetTypeHint(
      ffi.Pointer<ffi.NativeType> window, int hint);

  @ffi.Native<
      ffi.Void Function(
          ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gtk_window_set_transient_for',
  )
  external static void _gtkWindowSetTransientFor(
    ffi.Pointer<ffi.NativeType> window,
    ffi.Pointer<ffi.NativeType> parent,
  );

  @ffi.Native<
      ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.Uint8>)>(
    symbol: 'gtk_window_set_title',
  )
  external static void _gtkWindowSetTitle(
    ffi.Pointer<ffi.NativeType> window,
    ffi.Pointer<ffi.Uint8> title,
  );

  @ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gtk_window_get_title',
  )
  external static ffi.Pointer<ffi.Uint8> _gtkWindowGetTitle(
      ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int, ffi.Int)>(
    symbol: 'gtk_window_set_default_size',
  )
  external static void _gtkWindowSetDefaultSize(
    ffi.Pointer<ffi.NativeType> window,
    int width,
    int height,
  );

  @ffi.Native<
      ffi.Void Function(
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<GdkGeometry>,
        ffi.Int,
      )>(symbol: 'gtk_window_set_geometry_hints')
  external static void _gtkWindowSetGeometryHints(
    ffi.Pointer<ffi.NativeType> window,
    ffi.Pointer<ffi.NativeType> geometryWidget,
    ffi.Pointer<GdkGeometry> geometry,
    int geometryMask,
  );

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int, ffi.Int)>(
    symbol: 'gtk_window_resize',
  )
  external static void _gtkWindowResize(
      ffi.Pointer<ffi.NativeType> window, int width, int height);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int, ffi.Int)>(
    symbol: 'gtk_window_move',
  )
  external static void _gtkWindowMove(
      ffi.Pointer<ffi.NativeType> window, int x, int y);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_maximize')
  external static void _gtkWindowMaximize(ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_unmaximize')
  external static void _gtkWindowUnmaximize(ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_iconify')
  external static void _gtkWindowIconify(ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_deiconify')
  external static void _gtkWindowDeiconify(ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_fullscreen')
  external static void _gtkWindowFullscreen(ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_unfullscreen')
  external static void _gtkWindowUnfullscreen(
      ffi.Pointer<ffi.NativeType> window);

  @ffi.Native<
      ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.Int>,
          ffi.Pointer<ffi.Int>)>(symbol: 'gtk_window_get_size')
  external static void _gtkWindowGetSize(
    ffi.Pointer<ffi.NativeType> window,
    ffi.Pointer<ffi.Int> width,
    ffi.Pointer<ffi.Int> height,
  );

  @ffi.Native<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'gtk_window_is_active')
  external static bool _gtkWindowIsActive(ffi.Pointer<ffi.NativeType> widget);

  @ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Bool)>(
      symbol: 'gtk_widget_set_app_paintable')
  external static void _gtkWidgetSetAppPaintable(
      ffi.Pointer<ffi.NativeType> widget, bool appPaintable);

  // GTK Layer Shell methods

  /// Get the major version number of the GTK Layer Shell library.
  static int layerGetMajorVersion() {
    return _gtkLayerGetMajorVersion();
  }

  /// Get the minor version number of the GTK Layer Shell library.
  static int layerGetMinorVersion() {
    return _gtkLayerGetMinorVersion();
  }

  /// Get the micro version number of the GTK Layer Shell library.
  static int layerGetMicroVersion() {
    return _gtkLayerGetMicroVersion();
  }

  /// Check if the layer shell is supported on this system.
  static bool layerIsSupported() {
    return _gtkLayerIsSupported();
  }

  /// Get the Wayland layer shell protocol version.
  static int layerGetProtocolVersion() {
    return _gtkLayerGetProtocolVersion();
  }

  /// Initialize this window as a layer shell window.
  void layerInitForWindow() {
    _gtkLayerInitForWindow(instance);
  }

  /// Check if this window is a layer shell window.
  bool layerIsLayerWindow() {
    return _gtkLayerIsLayerWindow(instance);
  }

  /// Get the underlying zwlr_layer_surface_v1 pointer.
  ffi.Pointer<ffi.NativeType> layerGetZwlrLayerSurfaceV1() {
    return _gtkLayerGetZwlrLayerSurfaceV1(instance);
  }

  /// Set the namespace for this layer shell window.
  void layerSetNamespace(String namespace) {
    final ffi.Pointer<ffi.Uint8> namespaceBuffer = stringToNative(namespace);
    _gtkLayerSetNamespace(instance, namespaceBuffer);
    gFree(namespaceBuffer);
  }

  /// Get the namespace of this layer shell window.
  String layerGetNamespace() {
    return nativeToString(_gtkLayerGetNamespace(instance));
  }

  /// Set which layer this window appears on (background, bottom, top, overlay).
  void layerSetLayer(GtkLayerShellLayer layer) {
    _gtkLayerSetLayer(instance, layer.value);
  }

  /// Get which layer this window is on.
  GtkLayerShellLayer layerGetLayer() {
    final int value = _gtkLayerGetLayer(instance);
    return GtkLayerShellLayer.values[value];
  }

  /// Set which monitor this window appears on.
  void layerSetMonitor(ffi.Pointer<ffi.NativeType> monitor) {
    _gtkLayerSetMonitor(instance, monitor);
  }

  /// Get which monitor this window is on.
  ffi.Pointer<ffi.NativeType> layerGetMonitor() {
    return _gtkLayerGetMonitor(instance);
  }

  /// Set whether this window is anchored to an edge.
  void layerSetAnchor(GtkLayerShellEdge edge, bool anchorToEdge) {
    _gtkLayerSetAnchor(instance, edge.value, anchorToEdge);
  }

  /// Get whether this window is anchored to an edge.
  bool layerGetAnchor(GtkLayerShellEdge edge) {
    return _gtkLayerGetAnchor(instance, edge.value);
  }

  /// Set the margin from an edge.
  void layerSetMargin(GtkLayerShellEdge edge, int marginSize) {
    _gtkLayerSetMargin(instance, edge.value, marginSize);
  }

  /// Get the margin from an edge.
  int layerGetMargin(GtkLayerShellEdge edge) {
    return _gtkLayerGetMargin(instance, edge.value);
  }

  /// Set the exclusive zone (space reserved for this window).
  void layerSetExclusiveZone(int exclusiveZone) {
    _gtkLayerSetExclusiveZone(instance, exclusiveZone);
  }

  /// Get the exclusive zone.
  int layerGetExclusiveZone() {
    return _gtkLayerGetExclusiveZone(instance);
  }

  /// Enable automatic exclusive zone calculation.
  void layerAutoExclusiveZoneEnable() {
    _gtkLayerAutoExclusiveZoneEnable(instance);
  }

  /// Check if automatic exclusive zone is enabled.
  bool layerAutoExclusiveZoneIsEnabled() {
    return _gtkLayerAutoExclusiveZoneIsEnabled(instance);
  }

  /// Set the keyboard mode.
  void layerSetKeyboardMode(GtkLayerShellKeyboardMode mode) {
    _gtkLayerSetKeyboardMode(instance, mode.value);
  }

  /// Get the keyboard mode.
  GtkLayerShellKeyboardMode layerGetKeyboardMode() {
    final int value = _gtkLayerGetKeyboardMode(instance);
    return GtkLayerShellKeyboardMode.values[value];
  }

  /// Set keyboard interactivity (deprecated, use layerSetKeyboardMode instead).
  void layerSetKeyboardInteractivity(bool interactivity) {
    _gtkLayerSetKeyboardInteractivity(instance, interactivity);
  }

  /// Get keyboard interactivity (deprecated, use layerGetKeyboardMode instead).
  bool layerGetKeyboardInteractivity() {
    return _gtkLayerGetKeyboardInteractivity(instance);
  }

  /// Try to force commit changes to the compositor.
  void layerTryForceCommit() {
    _gtkLayerTryForceCommit(instance);
  }

  /// Set whether to respect compositor close requests.
  void layerSetRespectClose(bool respectClose) {
    _gtkLayerSetRespectClose(instance, respectClose);
  }

  /// Get whether the window respects compositor close requests.
  bool layerGetRespectClose() {
    return _gtkLayerGetRespectClose(instance);
  }

  // FFI bindings for GTK Layer Shell

  static final _gtkLayerGetMajorVersionPtr = gtkLayerShell
      .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
          'gtk_layer_get_major_version')
      .asFunction<int Function()>();
  static int _gtkLayerGetMajorVersion() => _gtkLayerGetMajorVersionPtr();

  static final _gtkLayerGetMinorVersionPtr = gtkLayerShell
      .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
          'gtk_layer_get_minor_version')
      .asFunction<int Function()>();
  static int _gtkLayerGetMinorVersion() => _gtkLayerGetMinorVersionPtr();

  static final _gtkLayerGetMicroVersionPtr = gtkLayerShell
      .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
          'gtk_layer_get_micro_version')
      .asFunction<int Function()>();
  static int _gtkLayerGetMicroVersion() => _gtkLayerGetMicroVersionPtr();

  static final _gtkLayerIsSupportedPtr = gtkLayerShell
      .lookup<ffi.NativeFunction<ffi.Bool Function()>>('gtk_layer_is_supported')
      .asFunction<bool Function()>();
  static bool _gtkLayerIsSupported() => _gtkLayerIsSupportedPtr();

  static final _gtkLayerGetProtocolVersionPtr = gtkLayerShell
      .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
          'gtk_layer_get_protocol_version')
      .asFunction<int Function()>();
  static int _gtkLayerGetProtocolVersion() => _gtkLayerGetProtocolVersionPtr();

  static final _gtkLayerInitForWindowPtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_init_for_window')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>)>();
  static void _gtkLayerInitForWindow(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerInitForWindowPtr(window);

  static final _gtkLayerIsLayerWindowPtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_is_layer_window')
      .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
  static bool _gtkLayerIsLayerWindow(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerIsLayerWindowPtr(window);

  static final _gtkLayerGetZwlrLayerSurfaceV1Ptr = gtkLayerShell
      .lookup<
              ffi.NativeFunction<
                  ffi.Pointer<ffi.NativeType> Function(
                      ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_get_zwlr_layer_surface_v1')
      .asFunction<
          ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>();
  static ffi.Pointer<ffi.NativeType> _gtkLayerGetZwlrLayerSurfaceV1(
          ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetZwlrLayerSurfaceV1Ptr(window);

  static final _gtkLayerSetNamespacePtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Pointer<ffi.Uint8>)>>('gtk_layer_set_namespace')
      .asFunction<
          void Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.Uint8>)>();
  static void _gtkLayerSetNamespace(ffi.Pointer<ffi.NativeType> window,
          ffi.Pointer<ffi.Uint8> namespace) =>
      _gtkLayerSetNamespacePtr(window, namespace);

  static final _gtkLayerGetNamespacePtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Pointer<ffi.Uint8> Function(
                  ffi.Pointer<ffi.NativeType>)>>('gtk_layer_get_namespace')
      .asFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>();
  static ffi.Pointer<ffi.Uint8> _gtkLayerGetNamespace(
          ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetNamespacePtr(window);

  static final _gtkLayerSetLayerPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(
                  ffi.Pointer<ffi.NativeType>, ffi.Int)>>('gtk_layer_set_layer')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int)>();
  static void _gtkLayerSetLayer(
          ffi.Pointer<ffi.NativeType> window, int layer) =>
      _gtkLayerSetLayerPtr(window, layer);

  static final _gtkLayerGetLayerPtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_get_layer')
      .asFunction<int Function(ffi.Pointer<ffi.NativeType>)>();
  static int _gtkLayerGetLayer(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetLayerPtr(window);

  static final _gtkLayerSetMonitorPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Pointer<ffi.NativeType>)>>('gtk_layer_set_monitor')
      .asFunction<
          void Function(
              ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.NativeType>)>();
  static void _gtkLayerSetMonitor(ffi.Pointer<ffi.NativeType> window,
          ffi.Pointer<ffi.NativeType> monitor) =>
      _gtkLayerSetMonitorPtr(window, monitor);

  static final _gtkLayerGetMonitorPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Pointer<ffi.NativeType> Function(
                  ffi.Pointer<ffi.NativeType>)>>('gtk_layer_get_monitor')
      .asFunction<
          ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>();
  static ffi.Pointer<ffi.NativeType> _gtkLayerGetMonitor(
          ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetMonitorPtr(window);

  static final _gtkLayerSetAnchorPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int,
                  ffi.Bool)>>('gtk_layer_set_anchor')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int, bool)>();
  static void _gtkLayerSetAnchor(
          ffi.Pointer<ffi.NativeType> window, int edge, bool anchorToEdge) =>
      _gtkLayerSetAnchorPtr(window, edge, anchorToEdge);

  static final _gtkLayerGetAnchorPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Bool Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Int)>>('gtk_layer_get_anchor')
      .asFunction<bool Function(ffi.Pointer<ffi.NativeType>, int)>();
  static bool _gtkLayerGetAnchor(
          ffi.Pointer<ffi.NativeType> window, int edge) =>
      _gtkLayerGetAnchorPtr(window, edge);

  static final _gtkLayerSetMarginPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int,
                  ffi.Int)>>('gtk_layer_set_margin')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int, int)>();
  static void _gtkLayerSetMargin(
          ffi.Pointer<ffi.NativeType> window, int edge, int marginSize) =>
      _gtkLayerSetMarginPtr(window, edge, marginSize);

  static final _gtkLayerGetMarginPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Int Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Int)>>('gtk_layer_get_margin')
      .asFunction<int Function(ffi.Pointer<ffi.NativeType>, int)>();
  static int _gtkLayerGetMargin(ffi.Pointer<ffi.NativeType> window, int edge) =>
      _gtkLayerGetMarginPtr(window, edge);

  static final _gtkLayerSetExclusiveZonePtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Int)>>('gtk_layer_set_exclusive_zone')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int)>();
  static void _gtkLayerSetExclusiveZone(
          ffi.Pointer<ffi.NativeType> window, int exclusiveZone) =>
      _gtkLayerSetExclusiveZonePtr(window, exclusiveZone);

  static final _gtkLayerGetExclusiveZonePtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_get_exclusive_zone')
      .asFunction<int Function(ffi.Pointer<ffi.NativeType>)>();
  static int _gtkLayerGetExclusiveZone(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetExclusiveZonePtr(window);

  static final _gtkLayerAutoExclusiveZoneEnablePtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_auto_exclusive_zone_enable')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>)>();
  static void _gtkLayerAutoExclusiveZoneEnable(
          ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerAutoExclusiveZoneEnablePtr(window);

  static final _gtkLayerAutoExclusiveZoneIsEnabledPtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_auto_exclusive_zone_is_enabled')
      .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
  static bool _gtkLayerAutoExclusiveZoneIsEnabled(
          ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerAutoExclusiveZoneIsEnabledPtr(window);

  static final _gtkLayerSetKeyboardModePtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Int)>>('gtk_layer_set_keyboard_mode')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int)>();
  static void _gtkLayerSetKeyboardMode(
          ffi.Pointer<ffi.NativeType> window, int mode) =>
      _gtkLayerSetKeyboardModePtr(window, mode);

  static final _gtkLayerGetKeyboardModePtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_get_keyboard_mode')
      .asFunction<int Function(ffi.Pointer<ffi.NativeType>)>();
  static int _gtkLayerGetKeyboardMode(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetKeyboardModePtr(window);

  static final _gtkLayerSetKeyboardInteractivityPtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Bool)>>('gtk_layer_set_keyboard_interactivity')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, bool)>();
  static void _gtkLayerSetKeyboardInteractivity(
          ffi.Pointer<ffi.NativeType> window, bool interactivity) =>
      _gtkLayerSetKeyboardInteractivityPtr(window, interactivity);

  static final _gtkLayerGetKeyboardInteractivityPtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_get_keyboard_interactivity')
      .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
  static bool _gtkLayerGetKeyboardInteractivity(
          ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetKeyboardInteractivityPtr(window);

  static final _gtkLayerTryForceCommitPtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_try_force_commit')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>)>();
  static void _gtkLayerTryForceCommit(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerTryForceCommitPtr(window);

  static final _gtkLayerSetRespectClosePtr = gtkLayerShell
      .lookup<
          ffi.NativeFunction<
              ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                  ffi.Bool)>>('gtk_layer_set_respect_close')
      .asFunction<void Function(ffi.Pointer<ffi.NativeType>, bool)>();
  static void _gtkLayerSetRespectClose(
          ffi.Pointer<ffi.NativeType> window, bool respectClose) =>
      _gtkLayerSetRespectClosePtr(window, respectClose);

  static final _gtkLayerGetRespectClosePtr = gtkLayerShell
      .lookup<
              ffi
              .NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
          'gtk_layer_get_respect_close')
      .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
  static bool _gtkLayerGetRespectClose(ffi.Pointer<ffi.NativeType> window) =>
      _gtkLayerGetRespectClosePtr(window);
}

/// Wraps FlView
class FlView extends GtkWidget {
  /// Create a new FlView widget.
  FlView()
      : super(
          _flViewNewForEngine(
            ffi.Pointer<ffi.NativeType>.fromAddress(
              WidgetsBinding.instance.platformDispatcher.engineId!,
            ),
          ),
        );

  /// Wrap an existing FlView handle (e.g. obtained via [getFlutterViewHandle]).
  // ignore: use_super_parameters
  FlView.fromHandle(ffi.Pointer<ffi.NativeType> handle) : super(handle);

  /// Get the ID for the Flutter view being shown in this widget.
  int getId() {
    return _flViewGetId(instance);
  }

  /// Set the background color of the FlView.
  void setBackgroundColor(String colorString) {
    final ffi.Pointer<GdkRGBA> color = gMalloc0(
      ffi.sizeOf<GdkRGBA>(),
    ).cast<GdkRGBA>();

    final ffi.Pointer<ffi.Uint8> colorBuffer = stringToNative(colorString);
    _gdkRgbaParse(color, colorBuffer);
    gFree(colorBuffer);

    _flViewSetBackgroundColor(instance, color);
    gFree(color);
  }

  @ffi.Native<
      ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'fl_view_new_for_engine',
  )
  external static ffi.Pointer<ffi.NativeType> _flViewNewForEngine(
    ffi.Pointer<ffi.NativeType> engine,
  );

  @ffi.Native<ffi.Int64 Function(ffi.Pointer<ffi.NativeType>)>(
      symbol: 'fl_view_get_id')
  external static int _flViewGetId(ffi.Pointer<ffi.NativeType> view);

  @ffi.Native<ffi.Bool Function(ffi.Pointer<GdkRGBA>, ffi.Pointer<ffi.Uint8>)>(
      symbol: 'gdk_rgba_parse')
  external static bool _gdkRgbaParse(
      ffi.Pointer<GdkRGBA> rgba, ffi.Pointer<ffi.Uint8> spec);

  @ffi.Native<
          ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<GdkRGBA>)>(
      symbol: 'fl_view_set_background_color')
  external static void _flViewSetBackgroundColor(
      ffi.Pointer<ffi.NativeType> view, ffi.Pointer<GdkRGBA> color);
}

/// Wraps FlWindowMonitor (helper object for handling signals from GtkWindow).
class FlWindowMonitor extends GObject {
  /// Create a new FlWindowMonitor.
  factory FlWindowMonitor(
    GtkWindow window,
    void Function() onConfigure,
    void Function() onStateChanged,
    void Function() onIsActiveNotify,
    void Function() onTitleNotify,
    void Function() onClose,
    void Function() onDestroy,
  ) {
    return FlWindowMonitor._internal(
      window.instance,
      ffi.NativeCallable<ffi.Void Function()>.isolateLocal(onConfigure),
      ffi.NativeCallable<ffi.Void Function()>.isolateLocal(onStateChanged),
      ffi.NativeCallable<ffi.Void Function()>.isolateLocal(onIsActiveNotify),
      ffi.NativeCallable<ffi.Void Function()>.isolateLocal(onTitleNotify),
      ffi.NativeCallable<ffi.Void Function()>.isolateLocal(onClose),
      ffi.NativeCallable<ffi.Void Function()>.isolateLocal(onDestroy),
    );
  }

  FlWindowMonitor._internal(
    ffi.Pointer<ffi.NativeType> window,
    this._onConfigureFunction,
    this._onStateChangedFunction,
    this._onIsActiveNotifyFunction,
    this._onTitleNotifyFunction,
    this._onCloseFunction,
    this._onDestroyFunction,
  ) : super(
          _flWindowMonitorNew(
            window,
            _onConfigureFunction.nativeFunction,
            _onStateChangedFunction.nativeFunction,
            _onIsActiveNotifyFunction.nativeFunction,
            _onTitleNotifyFunction.nativeFunction,
            _onCloseFunction.nativeFunction,
            _onDestroyFunction.nativeFunction,
          ),
        );

  final ffi.NativeCallable<ffi.Void Function()> _onConfigureFunction;
  final ffi.NativeCallable<ffi.Void Function()> _onStateChangedFunction;
  final ffi.NativeCallable<ffi.Void Function()> _onIsActiveNotifyFunction;
  final ffi.NativeCallable<ffi.Void Function()> _onTitleNotifyFunction;
  final ffi.NativeCallable<ffi.Void Function()> _onCloseFunction;
  final ffi.NativeCallable<ffi.Void Function()> _onDestroyFunction;

  /// Close all FFI resources used in the monitor.
  void close() {
    _onConfigureFunction.close();
    _onStateChangedFunction.close();
    _onIsActiveNotifyFunction.close();
    _onTitleNotifyFunction.close();
    _onCloseFunction.close();
    _onDestroyFunction.close();
  }

  @ffi.Native<
      ffi.Pointer<ffi.NativeType> Function(
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>,
        ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>,
        ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>,
        ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>,
        ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>,
        ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>,
      )>(symbol: 'fl_window_monitor_new')
  external static ffi.Pointer<ffi.NativeType> _flWindowMonitorNew(
    ffi.Pointer<ffi.NativeType> window,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> onConfigure,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> onStateChanged,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> onIsActiveNotify,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> onTitleNotify,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> onClose,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> onDestroy,
  );
}
