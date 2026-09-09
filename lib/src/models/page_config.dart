import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';

/// Paper sizes, expressed in PostScript points (1/72 inch) -- the same unit
/// the `pdf` package uses, so a page's on-screen geometry and its exported
/// geometry are the same numbers with no conversion step.
enum PaperSize {
  a3('A3', 841.89, 1190.55),
  a4('A4', 595.28, 841.89),
  a5('A5', 419.53, 595.28),
  letter('Letter', 612.0, 792.0),
  legal('Legal', 612.0, 1008.0);

  const PaperSize(this.label, this.portraitWidth, this.portraitHeight);

  final String label;
  final double portraitWidth;
  final double portraitHeight;
}

enum PageOrientation {
  portrait('Portrait'),
  landscape('Landscape');

  const PageOrientation(this.label);

  final String label;
}

/// Whether the document is a stack of discrete pages or one unbounded surface.
enum CanvasMode {
  /// Fixed-size pages laid out top-to-bottom. Strokes are clamped to the page
  /// width and a stroke's page index is derived from its y coordinate.
  paged('Pages'),

  /// A single unbounded 2D surface -- no page bands, no clamping, pan freely
  /// in both axes. Exporting crops to the drawn content.
  infinite('Infinite canvas');

  const CanvasMode(this.label);

  final String label;
}

/// The ruling printed underneath the ink.
enum PaperTemplate {
  blank('Blank'),
  lined('Lined'),
  grid('Squares'),
  dots('Dot grid'),
  cornell('Cornell notes');

  const PaperTemplate(this.label);

  final String label;
}

/// A paper size plus an orientation. Width/height are already swapped for
/// landscape, so callers never have to think about orientation again.
@immutable
class PageFormat {
  const PageFormat({
    this.size = PaperSize.a4,
    this.orientation = PageOrientation.portrait,
  });

  final PaperSize size;
  final PageOrientation orientation;

  static const PageFormat a4Portrait = PageFormat();

  bool get isLandscape => orientation == PageOrientation.landscape;

  double get width => isLandscape ? size.portraitHeight : size.portraitWidth;

  double get height => isLandscape ? size.portraitWidth : size.portraitHeight;

  Size get pageSize => Size(width, height);

  PdfPageFormat get pdfPageFormat => PdfPageFormat(width, height);

  String get label => '${size.label} ${orientation.label}';

  PageFormat copyWith({
    PaperSize? size,
    PageOrientation? orientation,
  }) {
    return PageFormat(
      size: size ?? this.size,
      orientation: orientation ?? this.orientation,
    );
  }

  /// Recovers a format from raw dimensions. Used when a persisted document
  /// carries only `canvas_width`/`canvas_height` and no explicit format --
  /// dimensions are matched within a point of tolerance to absorb rounding
  /// from JSON round-trips.
  static PageFormat? fromDimensions(double width, double height) {
    bool near(double a, double b) => (a - b).abs() < 1.0;
    for (final size in PaperSize.values) {
      if (near(width, size.portraitWidth) &&
          near(height, size.portraitHeight)) {
        return PageFormat(size: size);
      }
      if (near(width, size.portraitHeight) &&
          near(height, size.portraitWidth)) {
        return PageFormat(
          size: size,
          orientation: PageOrientation.landscape,
        );
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'size': size.name,
        'orientation': orientation.name,
      };

  static PageFormat fromJson(Map<String, dynamic> json) {
    return PageFormat(
      size: PaperSize.values.firstWhere(
        (s) => s.name == json['size'],
        orElse: () => PaperSize.a4,
      ),
      orientation: PageOrientation.values.firstWhere(
        (o) => o.name == json['orientation'],
        orElse: () => PageOrientation.portrait,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PageFormat &&
      other.size == size &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(size, orientation);

  @override
  String toString() => 'PageFormat($label)';
}

/// Colours and metrics for the ruling. Kept separate from the template enum so
/// the host app can tune it per theme -- the same `lined` template needs a
/// near-black rule on a dark page and a pale blue one on white.
@immutable
class PaperTemplateTheme {
  const PaperTemplateTheme({
    this.lineColor = const Color(0xFFB9C6D6),
    this.accentColor = const Color(0xFFE8A0A0),
    this.pageColor = const Color(0xFFFFFFFF),
    this.lineSpacing = 24.0,
    this.gridSpacing = 14.17,
    this.lineWidth = 0.6,
  });

  /// Ruled lines, grid lines and dots.
  final Color lineColor;

  /// Margin rules and Cornell dividers -- the lines that carry meaning rather
  /// than just guiding handwriting.
  final Color accentColor;

  /// The paper itself.
  final Color pageColor;

  /// Baseline-to-baseline distance for [PaperTemplate.lined], in points.
  /// 24pt is a shade over 8mm, the usual ruling for handwriting.
  final double lineSpacing;

  /// Cell pitch for [PaperTemplate.grid] and [PaperTemplate.dots].
  /// 14.17pt is 5mm.
  final double gridSpacing;

  final double lineWidth;

  static const PaperTemplateTheme light = PaperTemplateTheme();

  static const PaperTemplateTheme dark = PaperTemplateTheme(
    lineColor: Color(0xFF3A4250),
    accentColor: Color(0xFF5C4A4A),
    pageColor: Color(0xFF14181F),
  );

  // Value equality matters here: the painter's shouldRepaint compares themes,
  // and a host that rebuilds a theme inline each frame would otherwise force a
  // full repaint on every frame.
  @override
  bool operator ==(Object other) =>
      other is PaperTemplateTheme &&
      other.lineColor == lineColor &&
      other.accentColor == accentColor &&
      other.pageColor == pageColor &&
      other.lineSpacing == lineSpacing &&
      other.gridSpacing == gridSpacing &&
      other.lineWidth == lineWidth;

  @override
  int get hashCode => Object.hash(
        lineColor,
        accentColor,
        pageColor,
        lineSpacing,
        gridSpacing,
        lineWidth,
      );

  PaperTemplateTheme copyWith({
    Color? lineColor,
    Color? accentColor,
    Color? pageColor,
    double? lineSpacing,
    double? gridSpacing,
    double? lineWidth,
  }) {
    return PaperTemplateTheme(
      lineColor: lineColor ?? this.lineColor,
      accentColor: accentColor ?? this.accentColor,
      pageColor: pageColor ?? this.pageColor,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      lineWidth: lineWidth ?? this.lineWidth,
    );
  }
}
