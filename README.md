# layer_shell

A library to create panels and other desktop components for Wayland using the
[Layer Shell protocol](https://wayland.app/protocols/wlr-layer-shell-unstable-v1)
— powered by Flutter!

It wraps [`gtk-layer-shell`](https://github.com/wmww/gtk-layer-shell) via
`dart:ffi` and Flutter's Linux windowing support, letting you anchor Flutter
windows to screen edges, reserve exclusive space, and stack them on the
background/top/overlay layers — everything you need for bars, docks, wallpapers
and notification surfaces.

## Demo

https://github.com/user-attachments/assets/8eb5e841-f498-4873-b61e-4605048aa9ef

## ⚠️ Experimental

This package is built on Flutter's **experimental windowing APIs**, which are
private and change without notice — even in patch releases. As a consequence:

- It **cannot be published to pub.dev**. Consume it as a `path` or `git`
  dependency.
- It requires the Flutter **`main` channel**.

## Requirements

### System libraries

```sh
sudo apt install libgtk-3-dev libgtk-layer-shell-dev
```

`libgtk-layer-shell` is loaded at runtime via FFI, so it must be installed on
any machine that runs your app. A Wayland compositor implementing the layer
shell protocol (Miriway, miracle-wm, Sway, etc.) is required at runtime.

### Flutter

```sh
flutter channel main
flutter upgrade
flutter config --enable-windowing   # one-time
```

## Using the package

Add the dependency to your app's `pubspec.yaml`:

```yaml
dependencies:
  layer_shell:
    git:
      url: https://github.com/mattkae/layer_shell.dart.git
    # or, for local development:
    # path: ../layer_shell.dart
```

### Link gtk-layer-shell in your Linux runner

Because `gtk-layer-shell` is a system dependency, add it to your app's CMake
files.

In `linux/CMakeLists.txt`, next to the existing `pkg_check_modules(GTK ...)`:

```cmake
pkg_check_modules(GTK_LAYER_SHELL REQUIRED IMPORTED_TARGET gtk-layer-shell-0)
```

In `linux/runner/CMakeLists.txt`, next to the existing GTK link line:

```cmake
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK_LAYER_SHELL)
```

### Create a panel

Call `initLayerShell()` in `main()`, but create your controllers from **inside
the widget tree** (e.g. a `State`'s `initState`), not in `main()` — the GTK
windowing system must be fully up before the first surface is created.

```dart
import 'package:flutter/widgets.dart';
import 'package:layer_shell/layer_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initLayerShell(); // installs the windowing owner globally
  runWidget(const MyShell());
}

class MyShell extends StatefulWidget {
  const MyShell({super.key});
  @override
  State<MyShell> createState() => _MyShellState();
}

class _MyShellState extends State<MyShell> {
  late final LayershellWindowController _panel;

  @override
  void initState() {
    super.initState();
    final monitor = listMonitors().firstOrNull;
    _panel = LayershellWindowController(
      layer: LayerShellLayer.top,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      height: 40,
      exclusiveZone: 40,
      monitor: monitor?.gdkMonitor,
    );
  }

  @override
  void dispose() {
    _panel.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewCollection(
      views: [
        LayerShellWindow(
          controller: _panel,
          child: /* your panel content */,
        ),
      ],
    );
  }
}
```

## API overview

| Symbol | Purpose |
| --- | --- |
| `initLayerShell()` | Installs the windowing owner globally. Call once before creating controllers. |
| `LayershellWindowController` | Wraps a Flutter Linux window and applies layer-shell properties (layer, anchors, exclusive zone, keyboard mode, monitor). |
| `LayerShellWindow` | Widget that renders `child` into a controller's view. Place inside a `ViewCollection`. |
| `listMonitors()` / `MonitorInfo` | Enumerate connected monitors (name, model, position, handle). |
| `getScreenSize()` | Primary monitor size in logical pixels. |
| `DynamicLayerShellViews` | A `ChangeNotifier` singleton for adding/removing layer-shell views at runtime. |
| `anchorEdgesForPosition()` / `layerFromString()` | Helpers mapping `'top'`/`'bottom'`/`'left'`/`'right'` and layer names to enums. |
| `LayerShellLayer` / `LayerShellEdge` / `LayerShellKeyboardMode` | Layer-shell enums. |

## Example

A minimal single-panel demo lives in [`example/`](example/):

```sh
cd example
flutter pub get
flutter run -d linux
```

## License

GPLv3 — see [LICENSE](LICENSE).
