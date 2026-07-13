// WindowManager/WindowRegistry/WindowEntry are `@internal` in Flutter's
// experimental windowing API; suppress the internal-member lint here.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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

/// Each panel gets a wildly different colour so it is obvious at a glance that
/// they are three separate layer-shell surfaces rather than one window.
const Color _kTopPanelColor = Color(0xFF1E66F5); // blue
const Color _kBottomPanelColor = Color(0xFF40A02B); // green
const Color _kLeftPanelColor = Color(0xFFD20F39); // red

class _ExampleAppState extends State<_ExampleApp> {
  late final LayershellWindowController _panel;
  late final LayershellWindowController _bottomPanel;
  late final LayershellWindowController _leftPanel;
  late final LayershellWindowController _background;
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

    // Two more bars, anchored to the bottom and left edges. Each reserves its
    // own thickness, so the compositor keeps all three out of each other's way.
    _bottomPanel = LayershellWindowController(
      layer: LayerShellLayer.top,
      anchorEdges: const [
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.none,
      height: 48,
      exclusiveZone: 48,
      monitor: _monitor?.gdkMonitor,
    );

    _leftPanel = LayershellWindowController(
      layer: LayerShellLayer.top,
      anchorEdges: const [
        LayerShellEdge.left,
        LayerShellEdge.top,
        LayerShellEdge.bottom,
      ],
      keyboardMode: LayerShellKeyboardMode.none,
      width: 72,
      exclusiveZone: 72,
      monitor: _monitor?.gdkMonitor,
    );

    // A wallpaper on the bottom-most layer. Anchoring all four edges (with no
    // width/height) lets the compositor stretch it across the whole output, and
    // `exclusiveZone: -1` opts out of honouring *other* surfaces' exclusive
    // zones — without it the panel's 40px reservation would shrink this window
    // down to the space below the bar instead of running underneath it.
    //
    // Note this window accepts pointer input across the entire output: a
    // layer-shell surface gets a full input region by default, and the package
    // exposes no way to shrink it.
    _background = LayershellWindowController(
      layer: LayerShellLayer.background,
      anchorEdges: const [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.none,
      exclusiveZone: -1,
      monitor: _monitor?.gdkMonitor,
    );
  }

  @override
  void dispose() {
    _panel.destroy();
    _bottomPanel.destroy();
    _leftPanel.destroy();
    _background.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Each [LayerShellWindow] renders into its own controller's view, so a
    // [ViewCollection] is how one Flutter process drives several top-level
    // layer-shell surfaces at once.
    return ViewCollection(
      views: <Widget>[
        LayerShellWindow(
          controller: _background,
          child: const _LavaLampBackground(),
        ),
        // The panel's [LayerShellWindow] establishes the ambient [View] (and a
        // [WindowScope] exposing the panel controller). Nesting [WindowManager]
        // *inside* it means WindowManager takes its ViewAnchor branch (rendering
        // [child] plus any registered windows). Placed at the root instead,
        // WindowManager would drop its child.
        LayerShellWindow(
          controller: _panel,
          child: const WindowManager(child: _PanelBody()),
        ),
        LayerShellWindow(
          controller: _bottomPanel,
          child: const _EdgePanel(
            color: _kBottomPanelColor,
            label: 'bottom panel',
          ),
        ),
        LayerShellWindow(
          controller: _leftPanel,
          child: const _EdgePanel(
            color: _kLeftPanelColor,
            label: 'left',
            vertical: true,
          ),
        ),
      ],
    );
  }
}

/// A plain coloured bar for the bottom and left edges — no interaction, just a
/// visually unmistakable surface.
class _EdgePanel extends StatelessWidget {
  const _EdgePanel({
    required this.color,
    required this.label,
    this.vertical = false,
  });

  final Color color;
  final String label;

  /// Rotates the label a quarter turn so it reads along a side bar.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    Widget text = Text(
      label,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
    if (vertical) {
      text = RotatedBox(quarterTurns: 3, child: text);
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(color: color, child: Center(child: text)),
    );
  }
}

/// Fills the background window with an animated metaball ("lava lamp") effect,
/// painted on the GPU by `shaders/lava_lamp.frag`.
class _LavaLampBackground extends StatefulWidget {
  const _LavaLampBackground();

  @override
  State<_LavaLampBackground> createState() => _LavaLampBackgroundState();
}

class _LavaLampBackgroundState extends State<_LavaLampBackground>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  late final Ticker _ticker;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    // The ticker feeds a notifier that [_LavaLampPainter] repaints from, so
    // animating never rebuilds the widget tree. It starts once the shader is in.
    _ticker = createTicker(
      (Duration elapsed) => _seconds.value = elapsed.inMicroseconds / 1e6,
    );
    _loadShader();
  }

  Future<void> _loadShader() async {
    final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
      'shaders/lava_lamp.frag',
    );
    if (!mounted) {
      return;
    }
    setState(() => _shader = program.fragmentShader());
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentShader? shader = _shader;
    if (shader == null) {
      // The window's view is transparent, so paint *something* while the shader
      // program is still loading.
      return const ColoredBox(color: Color(0xFF120E20));
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _LavaLampPainter(shader: shader, seconds: _seconds),
    );
  }
}

class _LavaLampPainter extends CustomPainter {
  _LavaLampPainter({required this.shader, required this.seconds})
    : super(repaint: seconds);

  final ui.FragmentShader shader;
  final ValueListenable<double> seconds;

  @override
  void paint(Canvas canvas, Size size) {
    // Float slots are the shader's uniforms flattened in declaration order:
    // 0,1 = uSize, 2 = uTime.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, seconds.value);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_LavaLampPainter oldDelegate) =>
      oldDelegate.shader != shader;
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
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
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
        color: _kTopPanelColor,
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
