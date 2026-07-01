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

WindowingOwnerLinux? _owner;

/// Initializes layer-shell support and installs the windowing owner globally.
///
/// Call this once after `WidgetsFlutterBinding.ensureInitialized()` and before
/// creating any [LayershellWindowController].
void initLayerShell() {
  if (!isWindowingEnabled) {
    throw UnsupportedError(_kWindowingDisabledErrorMessage);
  }
  final owner = _owner ??= WindowingOwnerLinux();
  WidgetsBinding.instance.windowingOwner = owner;
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
    final owner = _owner;
    if (owner == null) {
      throw StateError(
          'initLayerShell() must be called before creating a LayershellWindowController.');
    }
    final inner = owner.createRegularWindowController(
            delegate: RegularWindowControllerDelegate(), resizable: false)
        as RegularWindowControllerLinux;
    return LayershellWindowController._wrap(
      inner,
      layer: layer,
      anchorEdges: anchorEdges,
      keyboardMode: keyboardMode,
      width: width,
      height: height,
      exclusiveZone: exclusiveZone,
      monitor: monitor,
    );
  }

  LayershellWindowController._wrap(
    this._inner, {
    required LayerShellLayer layer,
    required List<LayerShellEdge> anchorEdges,
    required LayerShellKeyboardMode keyboardMode,
    int? width,
    int? height,
    int? exclusiveZone,
    ffi.Pointer<ffi.NativeType>? monitor,
  }) : super.empty() {
    // Forward change notifications from the inner controller so listeners on
    // this wrapper (e.g. LayerShellWindow's ListenableBuilder) stay in sync.
    _inner.addListener(notifyListeners);

    // Apply layer-shell settings now — the GtkWindow exists but present() is
    // deferred to the first frame, satisfying gtk-layer-shell's ordering rule.
    final gtkWin = GtkWindow(_inner.windowHandle.cast());
    FlView.fromHandle(_inner.flutterViewHandle.cast())
        .setBackgroundColor('#00000000');

    gtkWin.layerInitForWindow();
    if (monitor != null && monitor.address != 0) {
      gtkWin.layerSetMonitor(monitor);
    }
    if (exclusiveZone != null) {
      gtkWin.layerAutoExclusiveZoneEnable();
      gtkWin.layerSetExclusiveZone(exclusiveZone);
    }
    for (final edge in anchorEdges) {
      gtkWin.layerSetAnchor(edge, true);
    }
    gtkWin.layerSetLayer(layer);
    gtkWin.layerSetKeyboardMode(keyboardMode);
    gtkWin.setSizeRequest(width ?? -1, height ?? -1);
    gtkWin.setDefaultSize(width ?? -1, height ?? -1);
    gtkWin.setAppPaintable(true);
  }

  final RegularWindowControllerLinux _inner;

  @override
  FlutterView get rootView => _inner.rootView;

  @override
  Size get contentSize => _inner.contentSize;

  @override
  void destroy() {
    _inner.removeListener(notifyListeners);
    _inner.destroy();
  }

  @override
  bool get isActivated => _inner.isActivated;

  @override
  void setSize(Size size) => _inner.setSize(size);

  @override
  void activate() => _inner.activate();

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
