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
    // The panel's [LayerShellWindow] establishes the ambient [View] (and a
    // [WindowScope] exposing the panel controller). Nesting [WindowManager]
    // *inside* it means WindowManager takes its ViewAnchor branch (rendering
    // [child] plus any registered windows). Placed at the root instead,
    // WindowManager would drop its child.
    return LayerShellWindow(
      controller: _panel,
      child: const WindowManager(
        child: _PanelBody(),
      ),
    );
  }
}

/// Hosts the panel UI and owns the popup window's lifecycle.
///
/// This lives *below* [WindowManager] so its [BuildContext] can resolve the
/// [WindowRegistry] (via [WindowRegistry.of]) and the parent panel controller
/// (via [WindowScope.of]).
class _PanelBody extends StatefulWidget {
  const _PanelBody();

  @override
  State<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends State<_PanelBody> {
  /// Keyed onto the button so its rect can anchor the popup.
  final GlobalKey _buttonKey = GlobalKey();
  PopupWindowController? _popup;

  void _toggle() {
    if (_popup != null) {
      // Closing routes through the delegate's onWindowDestroyed (below), which
      // unregisters the entry and clears state — the same path the compositor
      // takes when the popup auto-dismisses on focus loss.
      _popup!.destroy();
      return;
    }

    final registry = WindowRegistry.of(context);
    final box = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    // Rect in the panel window's coordinate space that the popup anchors to.
    final anchorRect = box.localToGlobal(Offset.zero) & box.size;

    late final WindowEntry entry;
    final controller = PopupWindowController(
      parent: WindowScope.of(context), // the panel controller
      anchorRect: anchorRect,
      positioner: const WindowPositioner(
        parentAnchor: WindowPositionerAnchor.bottomLeft,
        childAnchor: WindowPositionerAnchor.topLeft,
        offset: Offset(0, 4),
        constraintAdjustment: WindowPositionerConstraintAdjustment(
          flipY: true,
          slideX: true,
        ),
      ),
      preferredConstraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
      delegate: _PopupDelegate(() {
        registry.unregister(entry);
        if (mounted) {
          setState(() => _popup = null);
        }
      }),
    );
    entry = WindowEntry(
      controller: controller,
      builder: (_) => _PopupContents(onClose: controller.destroy),
    );
    registry.register(entry);
    setState(() => _popup = controller);
  }

  @override
  void dispose() {
    _popup?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PanelContents(
      buttonKey: _buttonKey,
      open: _popup != null,
      onToggle: _toggle,
    );
  }
}

/// Bridges the popup controller's [PopupWindowControllerDelegate.onWindowDestroyed]
/// callback (fired on close *and* on focus-loss auto-dismiss) to a closure.
class _PopupDelegate extends PopupWindowControllerDelegate {
  _PopupDelegate(this.onDestroyed);

  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() => onDestroyed();
}

class _PanelContents extends StatelessWidget {
  const _PanelContents({
    required this.buttonKey,
    required this.open,
    required this.onToggle,
  });

  final Key buttonKey;
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
              key: buttonKey,
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
    // The popup view is sized-to-content, so give it a definite size.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        color: const Color(0xFF313244),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Popup window',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFCDD6F4), fontSize: 16),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onClose,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF585B70),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Close',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFCDD6F4), fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
