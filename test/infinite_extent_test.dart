import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_canvas/paper_canvas.dart';

/// The infinite surface's size is internal, so it is observed through the
/// CustomPaint the canvas lays out — that is the drawable area a user can pan
/// and draw across.
Size paintedSurface(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(PaperCanvas),
    matching: find.byType(CustomPaint),
  );
  // The canvas's own painter is the largest CustomPaint in the subtree;
  // Material inserts smaller ones for ink and scrollbars.
  return tester
      .widgetList<CustomPaint>(finder)
      .map((p) => p.size)
      .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
}

Future<void> pumpCanvas(
  WidgetTester tester, {
  required CanvasMode mode,
  Size? minSize,
  double? margin,
  List<Stroke> strokes = const <Stroke>[],
}) async {
  final controller = PaperCanvasController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PaperCanvas(
          controller: controller,
          canvasMode: mode,
          multiPage: mode == CanvasMode.paged,
          infiniteCanvasMinSize: minSize ?? const Size(10000, 15000),
          infiniteCanvasMargin: margin ?? 2000,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (strokes.isNotEmpty) {
    controller.loadStrokesJson(strokes.map((s) => s.toJson()).toList());
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('an empty infinite canvas is at least the configured minimum',
      (tester) async {
    await pumpCanvas(tester, mode: CanvasMode.infinite);
    final size = paintedSurface(tester);

    // Regression: this was previously derived from the page size, giving a
    // ~3191x3684 surface on A4 -- far too small to feel unbounded.
    expect(size.width, greaterThanOrEqualTo(10000));
    expect(size.height, greaterThanOrEqualTo(15000));
  });

  testWidgets('the minimum is configurable', (tester) async {
    await pumpCanvas(
      tester,
      mode: CanvasMode.infinite,
      minSize: const Size(4000, 6000),
    );
    final size = paintedSurface(tester);
    expect(size.width, 4000);
    expect(size.height, 6000);
  });

  testWidgets('it grows past the minimum to keep margin beyond the content',
      (tester) async {
    await pumpCanvas(
      tester,
      mode: CanvasMode.infinite,
      minSize: const Size(1000, 1000),
      margin: 500,
      strokes: [
        Stroke(points: const <Offset>[Offset(0, 0), Offset(3000, 4000)]),
      ],
    );
    final size = paintedSurface(tester);

    // Content reaches (3000, 4000), so the surface must extend a margin past
    // it rather than stopping at the 1000x1000 minimum.
    expect(size.width, greaterThan(3000 + 400));
    expect(size.height, greaterThan(4000 + 400));
  });

  testWidgets('paged mode is unaffected and stays one page wide',
      (tester) async {
    await pumpCanvas(tester, mode: CanvasMode.paged);
    final size = paintedSurface(tester);

    // A4 portrait: the page width, not the infinite minimum.
    expect(size.width, closeTo(595.28, 0.5));
    expect(size.height, closeTo(841.89, 0.5));
  });
}
