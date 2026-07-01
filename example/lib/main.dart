import 'package:flutter/widgets.dart';
import 'package:layer_shell/layer_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Install the layer-shell windowing owner globally.
  initLayerShell();

  final monitors = listMonitors();
  final monitor = monitors.isNotEmpty ? monitors.first : null;

  // A single 40px bar anchored to the top edge of the screen. `exclusiveZone`
  // reserves that space so other windows don't draw underneath it.
  final panel = LayershellWindowController(
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

  runWidget(
    ViewCollection(
      views: [
        LayerShellWindow(
          controller: panel,
          child: const _PanelContents(),
        ),
      ],
    ),
  );
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
