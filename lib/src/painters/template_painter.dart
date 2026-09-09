import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/page_config.dart';

/// Where template geometry gets drawn.
///
/// The ruling is defined exactly once, in top-left page coordinates, and then
/// replayed into either a Flutter [Canvas] or a [PdfGraphics]. That is the
/// whole point of this indirection: if the screen and the PDF each had their
/// own copy of the Cornell layout maths they would drift apart, and the drift
/// would only ever be visible after printing.
abstract class TemplateSink {
  void line(Offset from, Offset to, Color color, double width);

  /// Draws a whole field of dots in one operation.
  ///
  /// Batched rather than one call per dot: an A4 dot grid is ~2,500 points, and
  /// emitting each as its own filled ellipse made the exported PDF an order of
  /// magnitude larger than every other template.
  void dots(List<Offset> centers, double radius, Color color);
}

class _CanvasTemplateSink implements TemplateSink {
  _CanvasTemplateSink(this.canvas, this.origin);

  final Canvas canvas;

  /// Page origin within the scrolling document, so page 3's ruling lands on
  /// page 3 rather than at the top of the canvas.
  final Offset origin;

  @override
  void line(Offset from, Offset to, Color color, double width) {
    canvas.drawLine(
      from + origin,
      to + origin,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..isAntiAlias = true,
    );
  }

  @override
  void dots(List<Offset> centers, double radius, Color color) {
    // Round-capped points: one draw call for the whole field.
    canvas.drawPoints(
      ui.PointMode.points,
      <Offset>[for (final c in centers) c + origin],
      Paint()
        ..color = color
        ..strokeWidth = radius * 2
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }
}

class _PdfTemplateSink implements TemplateSink {
  _PdfTemplateSink(this.graphics, this.pageHeight);

  final PdfGraphics graphics;

  /// PDF space puts the origin at the bottom-left with y growing upward, so
  /// every y is flipped against the page height on the way in.
  final double pageHeight;

  double _y(double y) => pageHeight - y;

  @override
  void line(Offset from, Offset to, Color color, double width) {
    graphics
      ..setStrokeColor(PdfColor.fromInt(color.toARGB32()))
      ..setLineWidth(width)
      ..setLineCap(PdfLineCap.butt)
      ..moveTo(from.dx, _y(from.dy))
      ..lineTo(to.dx, _y(to.dy))
      ..strokePath();
  }

  @override
  void dots(List<Offset> centers, double radius, Color color) {
    if (centers.isEmpty) return;
    // A zero-length round-capped segment renders as a dot, and costs two
    // operators instead of the four bezier curves drawEllipse emits. All the
    // dots go into a single path closed by one strokePath.
    graphics
      ..setStrokeColor(PdfColor.fromInt(color.toARGB32()))
      ..setLineWidth(radius * 2)
      ..setLineCap(PdfLineCap.round);
    for (final c in centers) {
      final double y = _y(c.dy);
      graphics
        ..moveTo(c.dx, y)
        ..lineTo(c.dx, y);
    }
    graphics.strokePath();
  }
}

/// Draws the paper ruling for a single page.
class PaperTemplateRenderer {
  const PaperTemplateRenderer._();

  /// Paints [template] over a page of [pageSize] into [sink].
  static void paint({
    required TemplateSink sink,
    required PaperTemplate template,
    required Size pageSize,
    required PaperTemplateTheme theme,
  }) {
    switch (template) {
      case PaperTemplate.blank:
        return;
      case PaperTemplate.lined:
        _paintLined(sink, pageSize, theme);
      case PaperTemplate.grid:
        _paintGrid(sink, pageSize, theme);
      case PaperTemplate.dots:
        _paintDots(sink, pageSize, theme);
      case PaperTemplate.cornell:
        _paintCornell(sink, pageSize, theme);
    }
  }

  /// Convenience wrapper for the on-screen painter.
  static void paintToCanvas({
    required Canvas canvas,
    required Offset origin,
    required PaperTemplate template,
    required Size pageSize,
    required PaperTemplateTheme theme,
  }) {
    paint(
      sink: _CanvasTemplateSink(canvas, origin),
      template: template,
      pageSize: pageSize,
      theme: theme,
    );
  }

  /// Convenience wrapper for PDF export.
  static void paintToPdf({
    required PdfGraphics graphics,
    required PaperTemplate template,
    required Size pageSize,
    required PaperTemplateTheme theme,
  }) {
    paint(
      sink: _PdfTemplateSink(graphics, pageSize.height),
      template: template,
      pageSize: pageSize,
      theme: theme,
    );
  }

  /// A `pw.Widget` that renders the ruling as vector paths, for composing into
  /// an exported page.
  static pw.Widget pdfWidget({
    required PaperTemplate template,
    required Size pageSize,
    required PaperTemplateTheme theme,
  }) {
    return pw.CustomPaint(
      size: PdfPoint(pageSize.width, pageSize.height),
      painter: (PdfGraphics graphics, PdfPoint _) => paintToPdf(
        graphics: graphics,
        template: template,
        pageSize: pageSize,
        theme: theme,
      ),
    );
  }

  // Ruled paper: a left margin rule plus evenly spaced baselines. The top
  // inset keeps the first baseline off the very edge of the sheet.
  static void _paintLined(
    TemplateSink sink,
    Size page,
    PaperTemplateTheme theme,
  ) {
    final double marginX = page.width * 0.11;
    final double topInset = theme.lineSpacing * 2;
    final double bottomInset = theme.lineSpacing;

    for (double y = topInset;
        y <= page.height - bottomInset;
        y += theme.lineSpacing) {
      sink.line(
        Offset(marginX, y),
        Offset(page.width - theme.lineSpacing, y),
        theme.lineColor,
        theme.lineWidth,
      );
    }

    // The margin rule carries meaning, so it is drawn heavier than the
    // baselines -- at the baseline weight it all but disappears in print.
    sink.line(
      Offset(marginX, theme.lineSpacing),
      Offset(marginX, page.height - theme.lineSpacing),
      theme.accentColor,
      theme.lineWidth * 2,
    );
  }

  static void _paintGrid(
    TemplateSink sink,
    Size page,
    PaperTemplateTheme theme,
  ) {
    final double step = theme.gridSpacing;
    for (double x = step; x < page.width; x += step) {
      sink.line(
        Offset(x, 0),
        Offset(x, page.height),
        theme.lineColor,
        theme.lineWidth,
      );
    }
    for (double y = step; y < page.height; y += step) {
      sink.line(
        Offset(0, y),
        Offset(page.width, y),
        theme.lineColor,
        theme.lineWidth,
      );
    }
  }

  static void _paintDots(
    TemplateSink sink,
    Size page,
    PaperTemplateTheme theme,
  ) {
    final double step = theme.gridSpacing;
    final double radius = theme.lineWidth * 1.4;
    final List<Offset> centers = <Offset>[];
    for (double x = step; x < page.width; x += step) {
      for (double y = step; y < page.height; y += step) {
        centers.add(Offset(x, y));
      }
    }
    sink.dots(centers, radius, theme.lineColor);
  }

  // Cornell layout: a title strip across the top, a cue column down the left,
  // a notes area filling the rest, and a summary band across the bottom.
  // Proportions rather than fixed inches, so the layout survives A5 and A3.
  static void _paintCornell(
    TemplateSink sink,
    Size page,
    PaperTemplateTheme theme,
  ) {
    final double headerY = page.height * 0.085;
    final double summaryY = page.height * 0.78;
    final double cueX = page.width * 0.3;

    // Title strip.
    sink.line(
      Offset(0, headerY),
      Offset(page.width, headerY),
      theme.accentColor,
      theme.lineWidth * 2,
    );

    // Cue / notes divider, stopping at the summary band.
    sink.line(
      Offset(cueX, headerY),
      Offset(cueX, summaryY),
      theme.accentColor,
      theme.lineWidth * 2,
    );

    // Summary divider.
    sink.line(
      Offset(0, summaryY),
      Offset(page.width, summaryY),
      theme.accentColor,
      theme.lineWidth * 2,
    );

    // Baselines through the notes column only -- the cue column is
    // deliberately left open for keywords and questions.
    for (double y = headerY + theme.lineSpacing;
        y < summaryY - theme.lineSpacing * 0.5;
        y += theme.lineSpacing) {
      sink.line(
        Offset(cueX + theme.lineSpacing * 0.4, y),
        Offset(page.width - theme.lineSpacing * 0.4, y),
        theme.lineColor,
        theme.lineWidth,
      );
    }

    // Baselines in the summary band.
    for (double y = summaryY + theme.lineSpacing;
        y < page.height - theme.lineSpacing * 0.5;
        y += theme.lineSpacing) {
      sink.line(
        Offset(theme.lineSpacing * 0.4, y),
        Offset(page.width - theme.lineSpacing * 0.4, y),
        theme.lineColor,
        theme.lineWidth,
      );
    }
  }
}

/// Rasterises one page of ruling into a [ui.Image].
///
/// Not used for on-screen drawing (which paints the ruling directly) but handy
/// for thumbnails, where composing a template behind the ink without standing
/// up the whole canvas widget is much cheaper.
Future<ui.Image> renderTemplateImage({
  required PaperTemplate template,
  required Size pageSize,
  required PaperTemplateTheme theme,
  double pixelRatio = 1.0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
    Paint()..color = theme.pageColor,
  );
  PaperTemplateRenderer.paintToCanvas(
    canvas: canvas,
    origin: Offset.zero,
    template: template,
    pageSize: pageSize,
    theme: theme,
  );
  return recorder.endRecording().toImage(
        (pageSize.width * pixelRatio).ceil(),
        (pageSize.height * pixelRatio).ceil(),
      );
}
