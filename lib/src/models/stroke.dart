import 'dart:math' as math;
import 'package:flutter/material.dart';

/// What produced a stroke.
///
/// Freehand strokes keep every sampled point. Shape strokes keep exactly two
/// -- the drag start and end -- and derive their outline on demand, so a
/// rectangle stays a rectangle through save/load rather than degrading into a
/// polyline that happens to look rectangular.
enum ScribeTool {
  /// Constant-width freehand.
  pen,

  /// Freehand whose width tracks drawing speed, giving an ink-like taper.
  brush,

  line,
  rectangle,
  circle,
  eraser;

  bool get isShape =>
      this == ScribeTool.line ||
      this == ScribeTool.rectangle ||
      this == ScribeTool.circle;

  /// Whether per-point widths are recorded while drawing. Only the brush
  /// varies; everything else renders at a single width.
  bool get isVariableWidth => this == ScribeTool.brush;
}

class Stroke {
  final List<Offset> points;
  final List<double> widths; // Per-point width (variable-width pen). May be empty for legacy strokes.
  final Color color;
  final double strokeWidth;
  final ScribeTool tool;

  Rect? _bounds;
  List<Offset>? _outline;

  Stroke({
    required this.points,
    List<double>? widths,
    this.color = Colors.black,
    this.strokeWidth = 4.0,
    this.tool = ScribeTool.pen,
  }) : widths = widths ?? [];

  bool get isEraser => tool == ScribeTool.eraser;

  /// Drops the memoised outline and bounds.
  ///
  /// [points] is mutated in place while a stroke is being drawn, and for
  /// shapes the outline is *derived* from those points rather than being the
  /// same list, so it would otherwise keep describing the shape as it was at
  /// the start of the drag.
  void invalidateGeometry() {
    _bounds = null;
    _outline = null;
  }

  /// How many points a stroke of this tool takes to be worth keeping.
  static const int _minShapePoints = 2;

  /// The polyline actually drawn and hit-tested.
  ///
  /// For [ScribeTool.pen] and [ScribeTool.eraser] this is just [points]. For
  /// shapes it is generated from the two anchor points, which keeps rendering,
  /// eraser hit-testing and PDF export all working off one representation.
  List<Offset> get outlinePoints {
    if (_outline != null) return _outline!;
    if (!tool.isShape || points.length < _minShapePoints) {
      return _outline = points;
    }

    final Offset a = points.first;
    final Offset b = points.last;

    switch (tool) {
      case ScribeTool.line:
        return _outline = <Offset>[a, b];
      case ScribeTool.rectangle:
        return _outline = <Offset>[
          a,
          Offset(b.dx, a.dy),
          b,
          Offset(a.dx, b.dy),
          a,
        ];
      case ScribeTool.circle:
        final Rect rect = Rect.fromPoints(a, b);
        final double rx = rect.width / 2;
        final double ry = rect.height / 2;
        final Offset c = rect.center;
        // 48 segments is smooth at print resolution without bloating the
        // serialized stroke -- the outline is derived, never persisted.
        const int segments = 48;
        return _outline = <Offset>[
          for (int i = 0; i <= segments; i++)
            Offset(
              c.dx + rx * math.cos(2 * math.pi * i / segments),
              c.dy + ry * math.sin(2 * math.pi * i / segments),
            ),
        ];
      case ScribeTool.pen:
      case ScribeTool.brush:
      case ScribeTool.eraser:
        return _outline = points;
    }
  }

  /// Calculates or returns the bounding box of the stroke.
  Rect get bounds {
    if (_bounds != null) return _bounds!;
    final List<Offset> pts = outlinePoints;
    if (pts.isEmpty) return Rect.zero;

    double minX = pts[0].dx;
    double maxX = pts[0].dx;
    double minY = pts[0].dy;
    double maxY = pts[0].dy;

    for (int i = 1; i < pts.length; i++) {
      final p = pts[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    return _bounds = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(strokeWidth / 2);
  }

  /// Accurate hit-testing: returns true if [p] is within [threshold] of any
  /// segment of this stroke.
  bool isPointNear(Offset p, double threshold) {
    // Fast bounding box culling
    if (!bounds.inflate(threshold).contains(p)) return false;

    // Fine-grained segment check
    final List<Offset> pts = outlinePoints;
    for (int i = 0; i < pts.length - 1; i++) {
      if (_distToSegment(p, pts[i], pts[i + 1]) <= threshold) {
        return true;
      }
    }
    return false;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final Offset v = b - a;
    final Offset w = p - a;
    final double c1 = w.dx * v.dx + w.dy * v.dy;
    if (c1 <= 0) return (p - a).distance;
    final double c2 = v.dx * v.dx + v.dy * v.dy;
    if (c2 <= c1) return (p - b).distance;
    final double bVal = c1 / c2;
    final Offset pb = a + v * bVal;
    return (p - pb).distance;
  }

  Stroke copyWith({
    List<Offset>? points,
    List<double>? widths,
    Color? color,
    double? strokeWidth,
    ScribeTool? tool,
  }) {
    return Stroke(
      points: points ?? this.points,
      widths: widths ?? this.widths,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      tool: tool ?? this.tool,
    );
  }

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
        'widths': widths,
        'width': strokeWidth,
        'color': color.toARGB32(),
        'isEraser': isEraser,
        'tool': tool.name,
      };

  static Stroke fromJson(Map<String, dynamic> json) {
    return Stroke(
      points: (json['points'] as List)
          .map(
            (p) => Offset(
              (p['dx'] as num).toDouble(),
              (p['dy'] as num).toDouble(),
            ),
          )
          .toList(),
      widths: json['widths'] != null
          ? (json['widths'] as List).map((w) => (w as num).toDouble()).toList()
          : [],
      color: Color((json['color'] as num).toInt()),
      strokeWidth: (json['width'] as num?)?.toDouble() ?? 1.0,
      tool: _toolFromJson(json),
    );
  }

  /// `tool` is the modern discriminator; `isEraser` is what documents written
  /// before shapes existed carry, so it is honoured as a fallback.
  static ScribeTool _toolFromJson(Map<String, dynamic> json) {
    final Object? raw = json['tool'];
    if (raw is String) {
      for (final t in ScribeTool.values) {
        if (t.name == raw) return t;
      }
    }
    return (json['isEraser'] as bool? ?? false)
        ? ScribeTool.eraser
        : ScribeTool.pen;
  }

  /// Simplifies the stroke using the Ramer-Douglas-Peucker algorithm.
  Stroke simplify([double epsilon = 0.5]) {
    // Shapes are already minimal -- two anchor points define them, and
    // discarding either would change the shape rather than smooth it.
    if (tool.isShape) return this;
    if (points.length <= 2) return this;

    final List<int> kept = _rdpIndices(points, epsilon);
    final List<Offset> simplifiedPoints = kept.map((i) => points[i]).toList();
    final List<double> simplifiedWidths =
        widths.isNotEmpty ? kept.map((i) => widths[i]).toList() : [];

    return Stroke(
      points: simplifiedPoints,
      widths: simplifiedWidths,
      color: color,
      strokeWidth: strokeWidth,
      tool: tool,
    );
  }

  /// Returns indices of kept points after RDP simplification.
  static List<int> _rdpIndices(List<Offset> points, double epsilon) {
    if (points.length <= 2) return List.generate(points.length, (i) => i);

    double maxDistance = 0.0;
    int index = 0;

    final Offset start = points.first;
    final Offset end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final double distance = _perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        index = i;
        maxDistance = distance;
      }
    }

    if (maxDistance > epsilon) {
      final List<int> left = _rdpIndices(points.sublist(0, index + 1), epsilon)
          .map((i) => i)
          .toList();
      final List<int> right = _rdpIndices(points.sublist(index), epsilon)
          .map((i) => i + index)
          .toList();
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [0, points.length - 1];
    }
  }

  static double _perpendicularDistance(Offset p, Offset start, Offset end) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    if (dx == 0 && dy == 0) return (p - start).distance;

    final double numerator =
        (dy * p.dx - dx * p.dy + end.dx * start.dy - end.dy * start.dx).abs();
    final double denominator = math.sqrt(dx * dx + dy * dy);
    return numerator / denominator;
  }

  /// Serializes the stroke into a compact string format.
  /// Format: isEraser|colorHex|strokeWidth|p1x,p1y;dx1,dy1;dx2,dy2...|w0,w1,w2...|tool
  ///
  /// The trailing tool segment is an addition to the upstream format. It is
  /// last and optional so that data written by an older build still parses.
  String serialize() {
    final buffer = StringBuffer();
    buffer.write(isEraser ? '1|' : '0|');
    buffer.write('${color.toARGB32().toRadixString(16).padLeft(8, '0')}|');
    buffer.write('${strokeWidth.toStringAsFixed(1)}|');

    if (points.isEmpty) {
      buffer.write('|'); // empty points section + empty widths
      return buffer.toString();
    }

    // Scale by 10 to keep 1 decimal place accuracy as integers
    int lastX = (points[0].dx * 10).round();
    int lastY = (points[0].dy * 10).round();
    buffer.write('$lastX,$lastY');

    for (int i = 1; i < points.length; i++) {
      final int currX = (points[i].dx * 10).round();
      final int currY = (points[i].dy * 10).round();
      final int dx = currX - lastX;
      final int dy = currY - lastY;
      buffer.write(';$dx,$dy');
      lastX = currX;
      lastY = currY;
    }

    // Append widths section (backwards-compatible: absent = legacy stroke)
    buffer.write('|');
    if (widths.isNotEmpty) {
      buffer.write(widths.map((w) => (w * 10).round()).join(','));
    }

    // Append tool section.
    buffer.write('|${tool.name}');

    return buffer.toString();
  }

  /// Deserializes a stroke from a compact string format.
  static Stroke deserialize(String data) {
    final parts = data.split('|');
    if (parts.length < 4) throw const FormatException('Invalid stroke data');

    final bool isEraser = parts[0] == '1';
    final Color color = Color(int.parse(parts[1], radix: 16));
    final double strokeWidth = double.parse(parts[2]);

    final List<Offset> points = [];
    final pointStrings = parts[3].split(';');

    if (pointStrings.isNotEmpty && pointStrings[0].isNotEmpty) {
      final firstPoint = pointStrings[0].split(',');
      int lastX = int.parse(firstPoint[0]);
      int lastY = int.parse(firstPoint[1]);
      points.add(Offset(lastX / 10.0, lastY / 10.0));

      for (int i = 1; i < pointStrings.length; i++) {
        final delta = pointStrings[i].split(',');
        final int dx = int.parse(delta[0]);
        final int dy = int.parse(delta[1]);
        lastX += dx;
        lastY += dy;
        points.add(Offset(lastX / 10.0, lastY / 10.0));
      }
    }

    // Deserialize widths (backwards-compatible: absent = legacy, use empty list)
    List<double> widths = [];
    if (parts.length >= 5 && parts[4].isNotEmpty) {
      widths = parts[4].split(',').map((s) => int.parse(s) / 10.0).toList();
    }

    ScribeTool tool = isEraser ? ScribeTool.eraser : ScribeTool.pen;
    if (parts.length >= 6 && parts[5].isNotEmpty) {
      for (final t in ScribeTool.values) {
        if (t.name == parts[5]) {
          tool = t;
          break;
        }
      }
    }

    return Stroke(
      points: points,
      widths: widths,
      color: color,
      strokeWidth: strokeWidth,
      tool: tool,
    );
  }
}
