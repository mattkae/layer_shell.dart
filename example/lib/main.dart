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

  @override
  void initState() {
    super.initState();
    final monitor = listMonitors().firstOrNull;

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
          child: const _PanelContents(),
        ),
      ],
    );
  }
}

class _PanelContents extends StatelessWidget {
  const _PanelContents();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF1E1E2E),
        child: Center(
          child: Text(
            'layer_shell example panel',
            style: const TextStyle(color: Color(0xFFCDD6F4), fontSize: 14),
          ),
        ),
      ),
    );
  }
}
