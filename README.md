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
| `LayershellWindowController` | Wraps a Flutter Linux window and applies layer-shell properties (layer, anchors, exclusive zone, margins, keyboard mode, monitor, namespace). |
| `LayerShellWindow` | Widget that renders `child` into a controller's view. Place inside a `ViewCollection`. |
| `listMonitors()` / `MonitorInfo` | Enumerate connected monitors (name, model, position, handle). |
| `getScreenSize()` | Primary monitor size in logical pixels. |
| `isLayerShellSupported()` | Whether the compositor advertises `zwlr_layer_shell_v1`. Call after `initLayerShell()`. |
| `layerShellProtocolVersion()` | The negotiated protocol version, for gating version-dependent behaviour. |
| `layerShellLibraryVersion()` | The loaded gtk-layer-shell version, as `"major.minor.micro"`. |
| `anchorEdgesForPosition()` / `layerFromString()` | Helpers mapping `'top'`/`'bottom'`/`'left'`/`'right'` and layer names to enums. |
| `LayerShellLayer` / `LayerShellEdge` / `LayerShellKeyboardMode` | Layer-shell enums. |

### Changing a surface after it is mapped

Every layer-shell property except the namespace can be changed at runtime:

| Member | Protocol request |
| --- | --- |
| `setLayer()` / `layer` | `set_layer` |
| `setAnchor()` / `getAnchor()` / `setAnchorEdges()` | `set_anchor` |
| `setMargin()` / `getMargin()` | `set_margin` |
| `setExclusiveZone()` / `exclusiveZone` | `set_exclusive_zone` |
| `enableAutoExclusiveZone()` / `autoExclusiveZoneEnabled` | `set_exclusive_zone`, recomputed from the window's size |
| `setKeyboardMode()` / `keyboardMode` | `set_keyboard_interactivity` |
| `setSize()` | `set_size` |
| `setMonitor()` / `monitor` | the `output` argument of `get_layer_surface` (recreates the surface) |
| `namespace` | the `namespace` argument of `get_layer_surface` (read-only; pass it to the constructor) |
| `setRespectClose()` / `respectClose` | whether a `closed` event is forwarded to GTK (needs gtk-layer-shell 0.10) |
| `destroy()` / `isDestroyed` | `destroy` |

A change made after the surface is mapped only *queues* a resize, so one that
does not itself cause a repaint may sit unsent until the next GTK frame. Call
`tryForceCommit()` to push it immediately:

```dart
panel.setLayer(LayerShellLayer.overlay);
panel.tryForceCommit();
```

The getters read gtk-layer-shell's record of what was *requested*, not what the
compositor acknowledged; `contentSize` is the exception and reports the size the
window actually has.

### Protocol coverage

This package covers every request in `zwlr_layer_shell_v1` /
`zwlr_layer_surface_v1` up to **protocol version 4**, which is what
gtk-layer-shell 0.10.0 implements. `ack_configure` and `get_popup` are handled
for you — the former inside gtk-layer-shell, the latter by Flutter's
`PopupWindowController` (see the example).

`set_exclusive_edge` (added in **protocol version 5**, for disambiguating which
edge an exclusive zone applies to when a surface is anchored to a corner) has no
`gtk_layer_*` wrapper and so cannot be issued through this package. If you need
it, `LayershellWindowController.zwlrLayerSurfaceHandle` exposes the raw
`zwlr_layer_surface_v1` proxy to marshal yourself — check
`layerShellProtocolVersion() >= 5` first, and note that requests sent that way
bypass gtk-layer-shell's cached state.

## Example

A minimal single-panel demo lives in [`example/`](example/):

```sh
cd example
flutter pub get
flutter run -d linux
```

## License

GPLv3 — see [LICENSE](LICENSE).
