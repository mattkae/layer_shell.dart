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
  WidgetsBinding.instance.windowingOwner = WindowingOwnerLinux();
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
      return [
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right
      ];
    case 'left':
      return [
        LayerShellEdge.left,
        LayerShellEdge.top,
        LayerShellEdge.bottom
      ];
    case 'right':
      return [
        LayerShellEdge.right,
        LayerShellEdge.top,
        LayerShellEdge.bottom
      ];
    default: // 'top'
      return [
        LayerShellEdge.top,
        LayerShellEdge.left,
        LayerShellEdge.right
      ];
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

/// Manages dynamically-created LayerShell windows (e.g. a notification panel)
/// for inclusion in the root ViewCollection.
class DynamicLayerShellViews extends ChangeNotifier {
  static final DynamicLayerShellViews instance = DynamicLayerShellViews._();
  DynamicLayerShellViews._();

  final List<Widget> _views = [];
  List<Widget> get views => List.unmodifiable(_views);

  void add(Widget view) {
    _views.add(view);
    notifyListeners();
  }

  void remove(Widget view) {
    _views.remove(view);
    notifyListeners();
  }
}

class LayershellWindowController extends RegularWindowController {
  /// Create a new LayershellWindowController.
  ///
  /// [initLayerShell] must have been called first.
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
    if (!_initialized) {
      throw StateError(
          'initLayerShell() must be called before creating a LayershellWindowController.');
    }
    final controller = LayershellWindowController._internal();
    controller._setup(
      layer: layer,
      anchorEdges: anchorEdges,
      keyboardMode: keyboardMode,
      width: width,
      height: height,
      exclusiveZone: exclusiveZone,
      monitor: monitor,
    );
    return controller;
  }

  // We create and own the GtkWindow ourselves (rather than wrapping Flutter's
  // RegularWindowControllerLinux) because gtk-layer-shell requires
  // gtk_layer_init_for_window() to run *before* the window is realized. Flutter's
  // controller realizes the window inside its constructor, which is too late.
  LayershellWindowController._internal()
      : _window = GtkWindow(GtkWindow.gtkWindowNew(0)), // GTK_WINDOW_TOPLEVEL
        super.empty();

  final GtkWindow _window;
  late final FlutterView _view;
  late final FlWindowMonitor _windowMonitor;
  bool _destroyed = false;

  void _setup({
    required LayerShellLayer layer,
    required List<LayerShellEdge> anchorEdges,
    required LayerShellKeyboardMode keyboardMode,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) {
    _windowMonitor = FlWindowMonitor(
      _window,
      notifyListeners, // onConfigure
      notifyListeners, // onStateChanged
      notifyListeners, // onIsActiveNotify
      notifyListeners, // onTitleNotify
      () {}, // onClose
      () {
        _destroyed = true;
        notifyListeners();
      }, // onDestroy
    );

    final view = FlView();
    view.setBackgroundColor('#00000000');
    final int viewId = view.getId();
    _view = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView v) => v.viewId == viewId,
    );

    // gtk-layer-shell requires init *before* the window is realized/mapped, so
    // apply every layer-shell setting before present().
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
    _window.add(view);
    _window.present();
    view.show();
  }

  @override
  FlutterView get rootView => _view;

  @override
  Size get contentSize => _window.getSize();

  @override
  void destroy() {
    if (_destroyed) return;
    _window.destroy();
    _windowMonitor.close();
    _windowMonitor.unref();
    _destroyed = true;
  }

  @override
  bool get isActivated => _window.isActive();

  @override
  void setSize(Size size) =>
      _window.resize(size.width.toInt(), size.height.toInt());

  @override
  void activate() => _window.present();

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
