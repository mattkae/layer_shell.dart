// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;
import 'package:flutter/src/widgets/_window_linux.dart';

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

// The generic GTK/GDK/Flutter wrappers (GObject, GtkWidget, GtkContainer,
// GtkWindow, GdkWindow, FlView, FlWindowMonitor, ...) now live in Flutter's
// `_window_linux.dart` and are imported above. This file only contains the
// gtk-layer-shell specific bindings (which Flutter does not ship) plus the GDK
// monitor/display helpers used by [listMonitors]/[getScreenSize], expressed as
// extensions on the Flutter-provided types.

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

/// Get the major version number of the GTK Layer Shell library.
int layerShellGetMajorVersion() => _gtkLayerGetMajorVersion();

/// Get the minor version number of the GTK Layer Shell library.
int layerShellGetMinorVersion() => _gtkLayerGetMinorVersion();

/// Get the micro version number of the GTK Layer Shell library.
int layerShellGetMicroVersion() => _gtkLayerGetMicroVersion();

/// Check if the layer shell is supported on this system.
bool layerShellIsSupported() => _gtkLayerIsSupported();

/// Get the Wayland layer shell protocol version.
int layerShellGetProtocolVersion() => _gtkLayerGetProtocolVersion();

/// gtk-layer-shell operations, plus the couple of GtkWidget tweaks the plugin
/// needs that are not surfaced by Flutter's [GtkWindow]. These call directly on
/// the underlying GtkWindow pointer ([GObject.instance]).
extension GtkWindowLayerShell on GtkWindow {
  /// Initialize this window as a layer shell window.
  ///
  /// Must be called *before* the window is realized/mapped.
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

  /// Sets a minimum size request for the widget.
  void setSizeRequest(int width, int height) {
    _gtkWidgetSetSizeRequest(instance, width, height);
  }

  /// Sets whether the application will paint directly on the widget.
  void setAppPaintable(bool appPaintable) {
    _gtkWidgetSetAppPaintable(instance, appPaintable);
  }
}

/// Flutter's [FlView] tweaks the plugin needs that are not surfaced by the SDK.
extension FlViewBackground on FlView {
  /// Set the background color of the FlView (e.g. '#00000000' for transparent).
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
}

// FFI bindings for the GtkWidget tweaks used by the extensions above.

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int, ffi.Int)>(
  symbol: 'gtk_widget_set_size_request',
)
external void _gtkWidgetSetSizeRequest(
    ffi.Pointer<ffi.NativeType> widget, int width, int height);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Bool)>(
    symbol: 'gtk_widget_set_app_paintable')
external void _gtkWidgetSetAppPaintable(
    ffi.Pointer<ffi.NativeType> widget, bool appPaintable);

@ffi.Native<ffi.Bool Function(ffi.Pointer<GdkRGBA>, ffi.Pointer<ffi.Uint8>)>(
    symbol: 'gdk_rgba_parse')
external bool _gdkRgbaParse(
    ffi.Pointer<GdkRGBA> rgba, ffi.Pointer<ffi.Uint8> spec);

@ffi.Native<
        ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<GdkRGBA>)>(
    symbol: 'fl_view_set_background_color')
external void _flViewSetBackgroundColor(
    ffi.Pointer<ffi.NativeType> view, ffi.Pointer<GdkRGBA> color);

// FFI bindings for GTK Layer Shell (dynamically loaded from libgtk-layer-shell).

final _gtkLayerGetMajorVersionPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
        'gtk_layer_get_major_version')
    .asFunction<int Function()>();
int _gtkLayerGetMajorVersion() => _gtkLayerGetMajorVersionPtr();

final _gtkLayerGetMinorVersionPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
        'gtk_layer_get_minor_version')
    .asFunction<int Function()>();
int _gtkLayerGetMinorVersion() => _gtkLayerGetMinorVersionPtr();

final _gtkLayerGetMicroVersionPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
        'gtk_layer_get_micro_version')
    .asFunction<int Function()>();
int _gtkLayerGetMicroVersion() => _gtkLayerGetMicroVersionPtr();

final _gtkLayerIsSupportedPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Bool Function()>>('gtk_layer_is_supported')
    .asFunction<bool Function()>();
bool _gtkLayerIsSupported() => _gtkLayerIsSupportedPtr();

final _gtkLayerGetProtocolVersionPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.UnsignedInt Function()>>(
        'gtk_layer_get_protocol_version')
    .asFunction<int Function()>();
int _gtkLayerGetProtocolVersion() => _gtkLayerGetProtocolVersionPtr();

final _gtkLayerInitForWindowPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_init_for_window')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>)>();
void _gtkLayerInitForWindow(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerInitForWindowPtr(window);

final _gtkLayerIsLayerWindowPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_is_layer_window')
    .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
bool _gtkLayerIsLayerWindow(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerIsLayerWindowPtr(window);

final _gtkLayerGetZwlrLayerSurfaceV1Ptr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Pointer<ffi.NativeType> Function(
                ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_get_zwlr_layer_surface_v1')
    .asFunction<
        ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>();
ffi.Pointer<ffi.NativeType> _gtkLayerGetZwlrLayerSurfaceV1(
        ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetZwlrLayerSurfaceV1Ptr(window);

final _gtkLayerSetNamespacePtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                ffi.Pointer<ffi.Uint8>)>>('gtk_layer_set_namespace')
    .asFunction<
        void Function(ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.Uint8>)>();
void _gtkLayerSetNamespace(ffi.Pointer<ffi.NativeType> window,
        ffi.Pointer<ffi.Uint8> namespace) =>
    _gtkLayerSetNamespacePtr(window, namespace);

final _gtkLayerGetNamespacePtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Pointer<ffi.Uint8> Function(
                ffi.Pointer<ffi.NativeType>)>>('gtk_layer_get_namespace')
    .asFunction<
        ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>();
ffi.Pointer<ffi.Uint8> _gtkLayerGetNamespace(
        ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetNamespacePtr(window);

final _gtkLayerSetLayerPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(
                ffi.Pointer<ffi.NativeType>, ffi.Int)>>('gtk_layer_set_layer')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int)>();
void _gtkLayerSetLayer(ffi.Pointer<ffi.NativeType> window, int layer) =>
    _gtkLayerSetLayerPtr(window, layer);

final _gtkLayerGetLayerPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_get_layer')
    .asFunction<int Function(ffi.Pointer<ffi.NativeType>)>();
int _gtkLayerGetLayer(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetLayerPtr(window);

final _gtkLayerSetMonitorPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                ffi.Pointer<ffi.NativeType>)>>('gtk_layer_set_monitor')
    .asFunction<
        void Function(
            ffi.Pointer<ffi.NativeType>, ffi.Pointer<ffi.NativeType>)>();
void _gtkLayerSetMonitor(ffi.Pointer<ffi.NativeType> window,
        ffi.Pointer<ffi.NativeType> monitor) =>
    _gtkLayerSetMonitorPtr(window, monitor);

final _gtkLayerGetMonitorPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Pointer<ffi.NativeType> Function(
                ffi.Pointer<ffi.NativeType>)>>('gtk_layer_get_monitor')
    .asFunction<
        ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>();
ffi.Pointer<ffi.NativeType> _gtkLayerGetMonitor(
        ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetMonitorPtr(window);

final _gtkLayerSetAnchorPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int,
                ffi.Bool)>>('gtk_layer_set_anchor')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int, bool)>();
void _gtkLayerSetAnchor(
        ffi.Pointer<ffi.NativeType> window, int edge, bool anchorToEdge) =>
    _gtkLayerSetAnchorPtr(window, edge, anchorToEdge);

final _gtkLayerGetAnchorPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Bool Function(ffi.Pointer<ffi.NativeType>,
                ffi.Int)>>('gtk_layer_get_anchor')
    .asFunction<bool Function(ffi.Pointer<ffi.NativeType>, int)>();
bool _gtkLayerGetAnchor(ffi.Pointer<ffi.NativeType> window, int edge) =>
    _gtkLayerGetAnchorPtr(window, edge);

final _gtkLayerSetMarginPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>, ffi.Int,
                ffi.Int)>>('gtk_layer_set_margin')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int, int)>();
void _gtkLayerSetMargin(
        ffi.Pointer<ffi.NativeType> window, int edge, int marginSize) =>
    _gtkLayerSetMarginPtr(window, edge, marginSize);

final _gtkLayerGetMarginPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Int Function(ffi.Pointer<ffi.NativeType>,
                ffi.Int)>>('gtk_layer_get_margin')
    .asFunction<int Function(ffi.Pointer<ffi.NativeType>, int)>();
int _gtkLayerGetMargin(ffi.Pointer<ffi.NativeType> window, int edge) =>
    _gtkLayerGetMarginPtr(window, edge);

final _gtkLayerSetExclusiveZonePtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                ffi.Int)>>('gtk_layer_set_exclusive_zone')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int)>();
void _gtkLayerSetExclusiveZone(
        ffi.Pointer<ffi.NativeType> window, int exclusiveZone) =>
    _gtkLayerSetExclusiveZonePtr(window, exclusiveZone);

final _gtkLayerGetExclusiveZonePtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_get_exclusive_zone')
    .asFunction<int Function(ffi.Pointer<ffi.NativeType>)>();
int _gtkLayerGetExclusiveZone(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetExclusiveZonePtr(window);

final _gtkLayerAutoExclusiveZoneEnablePtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_auto_exclusive_zone_enable')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>)>();
void _gtkLayerAutoExclusiveZoneEnable(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerAutoExclusiveZoneEnablePtr(window);

final _gtkLayerAutoExclusiveZoneIsEnabledPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_auto_exclusive_zone_is_enabled')
    .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
bool _gtkLayerAutoExclusiveZoneIsEnabled(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerAutoExclusiveZoneIsEnabledPtr(window);

final _gtkLayerSetKeyboardModePtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                ffi.Int)>>('gtk_layer_set_keyboard_mode')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, int)>();
void _gtkLayerSetKeyboardMode(ffi.Pointer<ffi.NativeType> window, int mode) =>
    _gtkLayerSetKeyboardModePtr(window, mode);

final _gtkLayerGetKeyboardModePtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_get_keyboard_mode')
    .asFunction<int Function(ffi.Pointer<ffi.NativeType>)>();
int _gtkLayerGetKeyboardMode(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetKeyboardModePtr(window);

final _gtkLayerSetKeyboardInteractivityPtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                ffi.Bool)>>('gtk_layer_set_keyboard_interactivity')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, bool)>();
void _gtkLayerSetKeyboardInteractivity(
        ffi.Pointer<ffi.NativeType> window, bool interactivity) =>
    _gtkLayerSetKeyboardInteractivityPtr(window, interactivity);

final _gtkLayerGetKeyboardInteractivityPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_get_keyboard_interactivity')
    .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
bool _gtkLayerGetKeyboardInteractivity(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetKeyboardInteractivityPtr(window);

final _gtkLayerTryForceCommitPtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_try_force_commit')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>)>();
void _gtkLayerTryForceCommit(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerTryForceCommitPtr(window);

final _gtkLayerSetRespectClosePtr = gtkLayerShell
    .lookup<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.NativeType>,
                ffi.Bool)>>('gtk_layer_set_respect_close')
    .asFunction<void Function(ffi.Pointer<ffi.NativeType>, bool)>();
void _gtkLayerSetRespectClose(
        ffi.Pointer<ffi.NativeType> window, bool respectClose) =>
    _gtkLayerSetRespectClosePtr(window, respectClose);

final _gtkLayerGetRespectClosePtr = gtkLayerShell
    .lookup<ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.NativeType>)>>(
        'gtk_layer_get_respect_close')
    .asFunction<bool Function(ffi.Pointer<ffi.NativeType>)>();
bool _gtkLayerGetRespectClose(ffi.Pointer<ffi.NativeType> window) =>
    _gtkLayerGetRespectClosePtr(window);
