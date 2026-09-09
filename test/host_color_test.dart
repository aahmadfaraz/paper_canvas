import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_canvas/paper_canvas.dart';

/// Host that drives the pen colour from outside the canvas, the way an app
/// with its own toolbar does.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.controller});

  final PaperCanvasController controller;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Color color = const Color(0xFF000000);

  /// The host changing its pen colour, the way a toolbar would.
  void setColor(Color value) => setState(() => color = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: PaperCanvas(controller: widget.controller, color: color),
      ),
    );
  }
}

void main() {
  /// Drags across the canvas to lay down one stroke.
  Future<void> draw(WidgetTester tester) async {
    final canvas = find.byType(PaperCanvas);
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(center + Offset(i * 6.0, i * 3.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a stroke uses the colour the host passes in', (tester) async {
    final controller = PaperCanvasController();
    addTearDown(controller.dispose);

    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, controller: controller));
    await tester.pumpAndSettle();

    // Host switches colour before anything is drawn. Upstream ignored the
    // `color` property entirely -- it seeded from `initialColor` in initState
    // and never looked at `color` again -- so every stroke came out black.
    key.currentState!.setColor(const Color(0xFFFF0000));
    await tester.pumpAndSettle();

    await draw(tester);

    final strokes = controller.getStrokesJson();
    expect(strokes, isNotEmpty, reason: 'the drag should have made a stroke');
    expect(Stroke.fromJson(strokes.last).color.toARGB32(), 0xFFFF0000);
  });

  testWidgets('changing colour mid-session only affects later strokes',
      (tester) async {
    final controller = PaperCanvasController();
    addTearDown(controller.dispose);

    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, controller: controller));
    await tester.pumpAndSettle();

    key.currentState!.setColor(const Color(0xFF00FF00));
    await tester.pumpAndSettle();
    await draw(tester);

    key.currentState!.setColor(const Color(0xFF0000FF));
    await tester.pumpAndSettle();
    await draw(tester);

    final strokes = controller.getStrokesJson();
    expect(strokes, hasLength(2));
    expect(Stroke.fromJson(strokes[0]).color.toARGB32(), 0xFF00FF00);
    expect(Stroke.fromJson(strokes[1]).color.toARGB32(), 0xFF0000FF);
  });
}
