// WindowManager/WindowRegistry/WindowEntry are `@internal` in Flutter's
// experimental windowing API; suppress the internal-member lint here.
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter/widgets.dart';
import 'package:layer_shell/layer_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Install the layer-shell windowing owner globally.
  initLayerShell();

  // Windows are created from within the widget tree (see [_ExampleAppState]),
  // not here in main(), so that the GTK windowing system is fully initialized
  // before the first surface is created.
  runWidget(const _ExampleApp());
}

class _ExampleApp extends StatefulWidget {
  const _ExampleApp();

  @override
  State<_ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<_ExampleApp> {
  late final LayershellWindowController _panel;
  MonitorInfo? _monitor;

  @override
  void initState() {
    super.initState();
    _monitor = listMonitors().firstOrNull;

    // A single 40px bar anchored to the top edge of the screen.
    // `exclusiveZone` reserves that space so other windows don't draw
    // underneath it.
    _panel = LayershellWindowController(
      layer: LayerShellLayer.top,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.none,
      height: 40,
      exclusiveZone: 40,
      monitor: _monitor?.gdkMonitor,
    );
  }

  @override
  void dispose() {
    _panel.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The panel's [LayerShellWindow] establishes the ambient [View]. Nesting
    // [WindowManager] *inside* it means WindowManager takes its ViewAnchor
    // branch (rendering [child] plus any registered windows). Placed at the root
    // instead, WindowManager would drop its child.
    return LayerShellWindow(
      controller: _panel,
      child: WindowManager(
        child: _PanelBody(monitor: _monitor),
      ),
    );
  }
}

/// Hosts the panel UI and owns the popup window's lifecycle.
///
/// This lives *below* [WindowManager] so its [BuildContext] can resolve the
/// [WindowRegistry] via [WindowRegistry.of].
class _PanelBody extends StatefulWidget {
  const _PanelBody({required this.monitor});

  final MonitorInfo? monitor;

  @override
  State<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends State<_PanelBody> {
  LayershellWindowController? _popup;
  WindowEntry? _entry;

  void _toggle() {
    final registry = WindowRegistry.of(context);
    setState(() {
      if (_popup != null) {
        registry.unregister(_entry!);
        _popup!.destroy();
        _popup = null;
        _entry = null;
      } else {
        // A small popup surface on the overlay layer. Anchoring to `top` only
        // (no left/right) centers it horizontally, and the panel's exclusive
        // zone pushes it just below the 40px bar.
        final controller = LayershellWindowController(
          layer: LayerShellLayer.overlay,
          anchorEdges: const [LayerShellEdge.top],
          keyboardMode: LayerShellKeyboardMode.none,
          width: 320,
          height: 200,
          monitor: widget.monitor?.gdkMonitor,
        );
        final entry = WindowEntry(
          controller: controller,
          builder: (_) => _PopupContents(onClose: _toggle),
        );
        registry.register(entry);
        _popup = controller;
        _entry = entry;
      }
    });
  }

  @override
  void dispose() {
    _popup?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PanelContents(open: _popup != null, onToggle: _toggle);
  }
}

class _PanelContents extends StatelessWidget {
  const _PanelContents({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF1E1E2E),
        child: Center(
          child: GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF45475A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                open ? 'Close popup' : 'Open popup',
                style: const TextStyle(color: Color(0xFFCDD6F4), fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopupContents extends StatelessWidget {
  const _PopupContents({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF313244),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Popup window',
                style: TextStyle(color: Color(0xFFCDD6F4), fontSize: 16),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF585B70),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Color(0xFFCDD6F4), fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
