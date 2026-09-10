import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_canvas/paper_canvas.dart';

/// Reads the paper colour the canvas actually painted, via the theme handed to
/// its painter — that is the single value the screen, the PDF and thumbnails
/// all derive the sheet colour from.
PaperTemplateTheme paintedTheme(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.descendant(
        of: find.byType(PaperCanvas),
        matching: find.byType(CustomPaint),
      ))
      .map((p) => p.painter)
      .whereType<PaperPainter>();
  expect(painters, isNotEmpty, reason: 'canvas painter not found');
  return painters.first.templateTheme;
}

Future<PaperCanvasController> pump(
  WidgetTester tester, {
  Color? canvasColor,
  PaperTemplateTheme? templateTheme,
  Color? penColor,
}) async {
  final controller = PaperCanvasController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PaperCanvas(
          controller: controller,
          canvasColor: canvasColor,
          templateTheme: templateTheme ?? PaperTemplateTheme.light,
          color: penColor ?? Colors.black,
          template: PaperTemplate.lined,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('canvasColor', () {
    testWidgets('defaults to white', (tester) async {
      await pump(tester);
      expect(paintedTheme(tester).pageColor.toARGB32(), 0xFFFFFFFF);
    });

    testWidgets('overrides the paper colour when given', (tester) async {
      await pump(tester, canvasColor: const Color(0xFFFFF8E1));
      expect(paintedTheme(tester).pageColor.toARGB32(), 0xFFFFF8E1);
    });

    testWidgets('leaves the rest of the template theme intact', (tester) async {
      const theme = PaperTemplateTheme(
        lineColor: Color(0xFF112233),
        accentColor: Color(0xFF445566),
        lineSpacing: 30,
      );
      await pump(
        tester,
        templateTheme: theme,
        canvasColor: const Color(0xFF000000),
      );

      final painted = paintedTheme(tester);
      expect(painted.pageColor.toARGB32(), 0xFF000000);
      // Only the paper changed; ruling colours and metrics are untouched.
      expect(painted.lineColor.toARGB32(), 0xFF112233);
      expect(painted.accentColor.toARGB32(), 0xFF445566);
      expect(painted.lineSpacing, 30);
    });

    testWidgets('falls back to the theme when null', (tester) async {
      // The dark preset must still work -- a non-null default here would have
      // silently overridden it.
      await pump(tester, templateTheme: PaperTemplateTheme.dark);
      expect(
        paintedTheme(tester).pageColor.toARGB32(),
        PaperTemplateTheme.dark.pageColor.toARGB32(),
      );
    });

    testWidgets('reaches the exported PDF, not just the screen',
        (tester) async {
      final controller =
          await pump(tester, canvasColor: const Color(0xFF102030));
      controller.loadStrokesJson([
        Stroke(
          points: const <Offset>[Offset(60, 100), Offset(200, 260)],
          color: const Color(0xFF222222),
        ).toJson(),
      ]);
      await tester.pumpAndSettle();

      final Uint8List? bytes = await controller.buildPdf();
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(0));
    });
  });

  group('default pen colour', () {
    testWidgets('is black', (tester) async {
      final controller = await pump(tester);
      final canvas = find.byType(PaperCanvas);
      final center = tester.getCenter(canvas);
      final gesture = await tester.startGesture(center);
      for (int i = 1; i <= 5; i++) {
        await gesture.moveTo(center + Offset(i * 8.0, i * 4.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final strokes = controller.getStrokesJson();
      expect(strokes, isNotEmpty);
      expect(Stroke.fromJson(strokes.last).color.toARGB32(), 0xFF000000);
    });

    testWidgets('is overridable via color', (tester) async {
      final controller = await pump(tester, penColor: const Color(0xFF00AA00));
      final canvas = find.byType(PaperCanvas);
      final center = tester.getCenter(canvas);
      final gesture = await tester.startGesture(center);
      for (int i = 1; i <= 5; i++) {
        await gesture.moveTo(center + Offset(i * 8.0, i * 4.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        Stroke.fromJson(controller.getStrokesJson().last).color.toARGB32(),
        0xFF00AA00,
      );
    });
  });
}
