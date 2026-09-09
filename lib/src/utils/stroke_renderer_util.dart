import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/stroke.dart';

class StrokeRendererUtil {
  // ─── Processing Pipeline ────────────────────────────────────────────────────

  /// Filters out micro-jitter and duplicate points.
  static Map<String, dynamic> filterPoints(
      List<Offset> points, List<double> widths) {
    if (points.isEmpty) return {'points': <Offset>[], 'widths': <double>[]};

    final List<Offset> filteredPts = [points.first];
    final List<double> filteredWts = widths.isNotEmpty ? [widths.first] : [];

    for (int i = 1; i < points.length; i++) {
      final distance = (points[i] - filteredPts.last).distance;
      if (distance > 0.5) {
        filteredPts.add(points[i]);
        if (i < widths.length) {
          filteredWts.add(widths[i]);
        }
      }
    }
    return {'points': filteredPts, 'widths': filteredWts};
  }

  /// Weighted moving average filter for points: P'[i] = 0.25*P[i-1] + 0.5*P[i] + 0.25*P[i+1]
  static List<Offset> smoothPoints(List<Offset> pts) {
    if (pts.length < 3) return pts;
    final List<Offset> smoothed = [pts.first];
    for (int i = 1; i < pts.length - 1; i++) {
      final Offset p =
          (pts[i - 1] * 0.25) + (pts[i] * 0.5) + (pts[i + 1] * 0.25);
      smoothed.add(p);
    }
    smoothed.add(pts.last);
    return smoothed;
  }

  /// Weighted moving average filter for widths.
  static List<double> smoothWidths(List<double> wts) {
    if (wts.length < 3) return wts;
    final List<double> smoothed = [wts.first];
    for (int i = 1; i < wts.length - 1; i++) {
      final double w =
          (wts[i - 1] * 0.25) + (wts[i] * 0.5) + (wts[i + 1] * 0.25);
      smoothed.add(w);
    }
    smoothed.add(wts.last);
    return smoothed;
  }

  /// Full processing pipeline: filtering + 2 smoothing passes.
  static Map<String, dynamic> processStroke(
      List<Offset> points, List<double> widths) {
    var filtered = filterPoints(points, widths);
    List<Offset> pts = filtered['points'];
    List<double> wts = filtered['widths'];

    if (pts.length < 3) return {'points': pts, 'widths': wts};

    for (int pass = 0; pass < 2; pass++) {
      pts = smoothPoints(pts);
      if (wts.isNotEmpty) {
        wts = smoothWidths(wts);
      }
    }
    return {'points': pts, 'widths': wts};
  }

  /// Generates the envelope (left/right edges) for a variable-width stroke.
  static Map<String, List<Offset>> generateEnvelope(
      List<Offset> pts, List<double> wts) {
    if (pts.length < 4) return {'left': [], 'right': []};

    final spline = CatmullRomSpline(pts);

    double totalDistance = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      totalDistance += (pts[i + 1] - pts[i]).distance;
    }

    // 1 sample every 0.5 pixels for ultra-smoothness
    final int samples = math.max(64, (totalDistance / 0.5).round());

    final List<Offset> rawLeftPoints = [];
    final List<Offset> rawRightPoints = [];

    final double taperFraction = 0.20;
    final int taperSamples = (samples * taperFraction).round();

    for (int i = 0; i <= samples; i++) {
      final double t = (i / samples).clamp(0.0, 1.0);
      final Offset point = spline.transform(t);

      final double segmentIndex = t * (pts.length - 1);
      final int idx = segmentIndex.floor().clamp(0, pts.length - 2);
      final double localT = (segmentIndex - idx).clamp(0.0, 1.0);
      double width = ui.lerpDouble(wts[idx], wts[idx + 1], localT) ?? wts[idx];

      if (i < taperSamples) {
        width *= (i / taperSamples);
      } else if (i > samples - taperSamples) {
        width *= ((samples - i) / taperSamples);
      }

      Offset tangent;
      if (i == 0) {
        tangent = spline.transform(1 / samples) - point;
      } else if (i == samples) {
        tangent = point - spline.transform((samples - 1) / samples);
      } else {
        tangent = spline.transform((i + 1) / samples) -
            spline.transform((i - 1) / samples);
      }

      final len = tangent.distance;
      final Offset normal =
          len < 0.0001 ? Offset.zero : Offset(-tangent.dy, tangent.dx) / len;

      rawLeftPoints.add(point + normal * (width / 2.0));
      rawRightPoints.add(point - normal * (width / 2.0));
    }

    return {
      'left': smoothPoints(rawLeftPoints),
      'right': smoothPoints(rawRightPoints),
    };
  }

  // ─── Drawing Methods ────────────────────────────────────────────────────────
  // These are shared by both the cache builder (PaperCanvasState._rebuildCache)
  // and the painter (PaperPainter) for the live current stroke.

  /// Draws a single stroke onto the given canvas using the full processing pipeline.
  static void drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    // Shapes bypass the freehand pipeline entirely. Smoothing a rectangle
    // would round its corners, and the variable-width envelope would give a
    // geometric figure the taper of a pen stroke.
    if (stroke.tool.isShape) {
      drawShapeOutline(canvas, stroke);
      return;
    }

    final processed = processStroke(stroke.points, stroke.widths);
    final List<Offset> smoothedPts = processed['points'];
    final List<double> smoothedWts = processed['widths'];

    if (smoothedWts.isNotEmpty &&
        smoothedWts.length == smoothedPts.length &&
        !stroke.isEraser) {
      drawVariableWidthStrokePolygon(
          canvas, smoothedPts, smoothedWts, stroke.color);
    } else {
      drawFixedWidthStrokeSpline(canvas, smoothedPts, stroke.color,
          stroke.strokeWidth, stroke.isEraser);
    }
  }

  /// Draws a shape stroke (line / rectangle / ellipse) as a constant-width
  /// outline. Shares [Stroke.outlinePoints] with hit-testing and PDF export so
  /// all three agree on where the shape actually is.
  static void drawShapeOutline(Canvas canvas, Stroke stroke) {
    final List<Offset> pts = stroke.outlinePoints;
    if (pts.length < 2) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  /// Catmull-Rom upsampling for fixed-width strokes (erasers or short strokes).
  static void drawFixedWidthStrokeSpline(Canvas canvas, List<Offset> pts,
      Color color, double strokeWidth, bool isEraser) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..blendMode = isEraser ? BlendMode.clear : BlendMode.srcOver;

    if (pts.length < 4) {
      canvas.drawPoints(ui.PointMode.polygon, pts, paint);
      return;
    }

    final spline = CatmullRomSpline(pts);
    final int samples = pts.length * 6;
    final path = Path();

    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i <= samples; i++) {
      final Offset p = spline.transform(i / samples);
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(path, paint);
  }

  /// Variable-width stroke using a polygon envelope (Google Docs style renderer).
  static void drawVariableWidthStrokePolygon(
      Canvas canvas, List<Offset> pts, List<double> wts, Color color) {
    if (pts.length < 4) {
      final paint = Paint()
        ..color = color
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      if (pts.length == 1) {
        paint.strokeWidth = wts[0];
        canvas.drawPoints(ui.PointMode.points, [pts[0]], paint);
      } else if (pts.length == 2) {
        paint.strokeWidth = (wts[0] + wts[1]) / 2;
        canvas.drawLine(pts[0], pts[1], paint);
      } else {
        paint.strokeWidth = (wts[0] + wts[1]) / 2;
        canvas.drawLine(pts[0], pts[1], paint);
        paint.strokeWidth = (wts[1] + wts[2]) / 2;
        canvas.drawLine(pts[1], pts[2], paint);
      }
      return;
    }

    final envelope = generateEnvelope(pts, wts);
    final List<Offset> leftPoints = envelope['left']!;
    final List<Offset> rightPoints = envelope['right']!;

    final Path path = Path();
    if (leftPoints.isNotEmpty) {
      bool pathStarted = false;

      void drawSide(List<Offset> points, bool reverse) {
        if (points.isEmpty) return;
        final List<Offset> ordered =
            reverse ? points.reversed.toList() : points;
        if (!pathStarted) {
          path.moveTo(ordered[0].dx, ordered[0].dy);
          pathStarted = true;
        } else {
          path.lineTo(ordered[0].dx, ordered[0].dy);
        }
        for (int i = 1; i < ordered.length; i++) {
          path.lineTo(ordered[i].dx, ordered[i].dy);
        }
      }

      drawSide(leftPoints, false);
      drawSide(rightPoints, true);
      path.close();
    }

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    // Thin outline with round joins to hide polygon facets
    final strokePaint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);
  }
}
