import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribe_canvas/scribe_canvas.dart';

/// Mounts a canvas, loads [strokes] into it and returns the exported bytes.
Future<Uint8List?> exportWith(
  WidgetTester tester, {
  required List<Stroke> strokes,
  ScribePageFormat pageFormat = ScribePageFormat.a4Portrait,
  ScribeCanvasMode canvasMode = ScribeCanvasMode.paged,
  ScribePaperTemplate template = ScribePaperTemplate.blank,
}) async {
  final controller = ScribeCanvasController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScribeCanvas(
          controller: controller,
          pageFormat: pageFormat,
          canvasMode: canvasMode,
          template: template,
          multiPage: canvasMode == ScribeCanvasMode.paged,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  controller.loadStrokesJson(strokes.map((s) => s.toJson()).toList());
  await tester.pumpAndSettle();

  return controller.buildPdf();
}

Stroke penStroke({double y = 100}) => Stroke(
      points: <Offset>[
        for (int i = 0; i < 20; i++) Offset(60.0 + i * 12, y + (i % 4) * 6),
      ],
      widths: <double>[for (int i = 0; i < 20; i++) 2.0 + (i % 3)],
      color: const Color(0xFF202020),
      strokeWidth: 4,
      tool: ScribeTool.brush,
    );

void main() {
  /// The PDF header. Asserting on it proves `pdf.save()` produced a real
  /// document rather than an empty or truncated buffer.
  bool looksLikePdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; // F

  /// Counts page objects. The `pdf` package emits one `/Type /Page` per page
  /// (the document catalogue uses `/Type /Pages`, hence the trailing space).
  int countPages(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
  }

  testWidgets('exports a valid PDF', (tester) async {
    final bytes = await exportWith(tester, strokes: [penStroke()]);

    expect(bytes, isNotNull);
    expect(looksLikePdf(bytes!), isTrue);
    expect(countPages(bytes), 1);
  });

  testWidgets('returns null when nothing is drawn', (tester) async {
    expect(await exportWith(tester, strokes: const []), isNull);
  });

  testWidgets('honours the selected page format', (tester) async {
    // A4 portrait and A3 landscape must not produce identically sized pages.
    final a4 = await exportWith(tester, strokes: [penStroke()]);
    final a3 = await exportWith(
      tester,
      strokes: [penStroke()],
      pageFormat: const ScribePageFormat(
        size: ScribePaperSize.a3,
        orientation: ScribePageOrientation.landscape,
      ),
    );

    expect(looksLikePdf(a4!), isTrue);
    expect(looksLikePdf(a3!), isTrue);

    // A3 landscape is 1190.55 x 841.89; A4 portrait is 595.28 x 841.89.
    expect(String.fromCharCodes(a3), contains('1190.55'));
    expect(String.fromCharCodes(a4), isNot(contains('1190.55')));
  });

  testWidgets('grows to one page per band of ink', (tester) async {
    // Ink on the third A4 page should produce three pages.
    final bytes = await exportWith(
      tester,
      strokes: [penStroke(y: 100), penStroke(y: 2000)],
    );

    expect(countPages(bytes!), 3);
  });

  testWidgets('an infinite canvas fits onto a single page', (tester) async {
    final bytes = await exportWith(
      tester,
      canvasMode: ScribeCanvasMode.infinite,
      strokes: [penStroke(y: 100), penStroke(y: 4000)],
    );

    expect(looksLikePdf(bytes!), isTrue);
    // Infinite mode scales the drawn region to fit, rather than slicing it.
    expect(countPages(bytes), 1);
  });

  testWidgets('templates add vector geometry to the page', (tester) async {
    final blank = await exportWith(
      tester,
      strokes: [penStroke()],
      template: ScribePaperTemplate.blank,
    );
    final cornell = await exportWith(
      tester,
      strokes: [penStroke()],
      template: ScribePaperTemplate.cornell,
    );

    // The ruling is drawn as real paths, so a templated page carries strictly
    // more content than a blank one.
    expect(cornell!.length, greaterThan(blank!.length));
  });

  _reconfigurationTests();

  testWidgets('shape strokes export as outlines', (tester) async {
    final bytes = await exportWith(
      tester,
      strokes: [
        Stroke(
          points: const <Offset>[Offset(80, 120), Offset(320, 400)],
          color: const Color(0xFF3355FF),
          strokeWidth: 3,
          tool: ScribeTool.rectangle,
        ),
      ],
    );

    expect(bytes, isNotNull);
    expect(looksLikePdf(bytes!), isTrue);
    expect(countPages(bytes), 1);
  });
}

/// Host that can swap the canvas geometry after the first build, exercising
/// `didUpdateWidget` the way the page-setup sheet does.
class _Reconfigurable extends StatefulWidget {
  const _Reconfigurable({super.key, required this.controller});

  final ScribeCanvasController controller;

  @override
  State<_Reconfigurable> createState() => _ReconfigurableState();
}

class _ReconfigurableState extends State<_Reconfigurable> {
  ScribePageFormat format = ScribePageFormat.a4Portrait;
  ScribeCanvasMode mode = ScribeCanvasMode.paged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ScribeCanvas(
          controller: widget.controller,
          pageFormat: format,
          canvasMode: mode,
          multiPage: mode == ScribeCanvasMode.paged,
        ),
      ),
    );
  }
}

void _reconfigurationTests() {
  testWidgets('changing page size re-derives the page count', (tester) async {
    final controller = ScribeCanvasController();
    addTearDown(controller.dispose);

    final key = GlobalKey<_ReconfigurableState>();
    await tester.pumpWidget(_Reconfigurable(key: key, controller: controller));
    await tester.pumpAndSettle();

    // Ink at y=2000 is on the third A4 page (842pt each).
    controller.loadStrokesJson([penStroke(y: 100).toJson(), penStroke(y: 2000).toJson()]);
    await tester.pumpAndSettle();
    expect(controller.pageCount, 3);

    // The same ink on A3 (1190.55pt tall) needs only two pages.
    key.currentState!.setState(() {
      key.currentState!.format =
          const ScribePageFormat(size: ScribePaperSize.a3);
    });
    await tester.pumpAndSettle();
    expect(controller.pageCount, 2);
  });

  testWidgets('switching to infinite collapses to a single page',
      (tester) async {
    final controller = ScribeCanvasController();
    addTearDown(controller.dispose);

    final key = GlobalKey<_ReconfigurableState>();
    await tester.pumpWidget(_Reconfigurable(key: key, controller: controller));
    await tester.pumpAndSettle();

    controller.loadStrokesJson([penStroke(y: 100).toJson(), penStroke(y: 2000).toJson()]);
    await tester.pumpAndSettle();
    expect(controller.pageCount, 3);

    key.currentState!.setState(() {
      key.currentState!.mode = ScribeCanvasMode.infinite;
    });
    await tester.pumpAndSettle();
    expect(controller.pageCount, 1);

    // And the export follows the new geometry.
    final bytes = await controller.buildPdf();
    expect(bytes, isNotNull);
  });
}
