## 0.3.0

Completes coverage of the layer-shell requests that `gtk-layer-shell` exposes.
Everything except the namespace can now be changed after the surface is mapped,
not just at construction.

- `LayershellWindowController` gains runtime `setLayer` / `layer`,
  `setAnchor` / `getAnchor` / `setAnchorEdges`,
  `setKeyboardMode` / `keyboardMode`, `setMonitor` / `monitor`, `namespace`,
  `enableAutoExclusiveZone` / `autoExclusiveZoneEnabled`,
  `setRespectClose` / `respectClose` (needs gtk-layer-shell 0.10), and the
  `zwlrLayerSurfaceHandle` escape hatch.
- New constructor arguments `namespace` (the `get_layer_surface` namespace, which
  compositors use in window rules) and `autoExclusiveZone`.
- **Fixed:** passing `exclusiveZone` also called
  `gtk_layer_auto_exclusive_zone_enable()`, which the following
  `gtk_layer_set_exclusive_zone()` immediately undid. Automatic zones are now
  reachable through `autoExclusiveZone:` / `enableAutoExclusiveZone()` instead.
- New top-level `isLayerShellSupported()`, `layerShellProtocolVersion()` and
  `layerShellLibraryVersion()`.
- `set_exclusive_edge` (protocol version 5) remains unavailable: gtk-layer-shell
  0.10.0 has no wrapper for it. See the protocol coverage note in the README.

## 0.2.0

- `LayershellWindowController.isDestroyed`.
- Runtime `setMargin` / `getMargin` and `setExclusiveZone` / `exclusiveZone`.
- `tryForceCommit()`, which pushes queued layer-shell state to the compositor
  without waiting for the next GTK frame. Returns false on gtk-layer-shell
  older than 0.9.

## 0.1.0

- Initial extraction of layer-shell support from graceful-shell.
- Provides `LayershellWindowController`, `LayerShellWindow`, `listMonitors`,
  and the `GtkLayerShellLayer` / `GtkLayerShellEdge` /
  `GtkLayerShellKeyboardMode` enums.
