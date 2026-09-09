import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert'; // Added for JSON encoding/decoding
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:paper_canvas/src/utils/stroke_renderer_util.dart';
import '../controllers/paper_canvas_controller.dart';
import '../models/page_config.dart';
import '../models/stroke.dart';
import '../painters/paper_painter.dart';
import '../painters/template_painter.dart';
import 'page_header.dart';

enum ScrollMode {
  continuous,
  discrete,
}

class PaperCanvas extends StatefulWidget {
  final PaperCanvasController? controller;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final bool isPanMode;
  final VoidCallback? onStrokeStart;
  final VoidCallback? onStrokeEnd;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<double>? onStrokeWidthChanged;
  final List<double> strokeSizes;
  final double eraserWidth;
  final List<double> eraserSizes;
  final ValueChanged<double>? onEraserWidthChanged;
  final ValueChanged<bool>? onToggleEraser;
  final bool multiPage;
  final List<Color> colors;
  final Color initialColor;
  final ValueChanged<Color>? onColorChanged;
  final IconData eraserIcon;
  final double eraserIconSize;
  final Color eraserActiveColor;
  final Color eraserInactiveColor;
  final ScrollMode scrollMode;
  final int initialPageIndex;

  /// Paper size and orientation. In [CanvasMode.infinite] this is used
  /// only as the export page size -- the drawing surface itself is unbounded.
  final PageFormat pageFormat;

  /// Whether the surface is a stack of pages or one unbounded canvas.
  final CanvasMode canvasMode;

  /// The ruling drawn under the ink.
  final PaperTemplate template;

  /// Colours and metrics for that ruling.
  final PaperTemplateTheme templateTheme;

  /// The active tool. When null, falls back to [isEraser] so that callers
  /// written against the pen/eraser-only API keep working.
  final PaperTool? tool;

  /// Minimum size of the drawing surface in [CanvasMode.infinite].
  ///
  /// This is the room available before anything is drawn; the surface then
  /// grows beyond it to keep [infiniteCanvasMargin] of slack past the content.
  /// Deliberately far larger than a page -- a canvas that only extends a
  /// screen or two in each direction does not feel unbounded.
  final Size infiniteCanvasMinSize;

  /// Slack kept beyond the drawn content in [CanvasMode.infinite], so there is
  /// always somewhere left to pan into and keep drawing.
  final double infiniteCanvasMargin;

  const PaperCanvas({
    super.key,
    this.controller,
    this.color = Colors.black,
    this.strokeWidth = 4.0,
    this.isEraser = false,
    this.tool,
    this.pageFormat = PageFormat.a4Portrait,
    this.canvasMode = CanvasMode.paged,
    this.infiniteCanvasMinSize = const Size(10000, 15000),
    this.infiniteCanvasMargin = 2000,
    this.template = PaperTemplate.blank,
    this.templateTheme = PaperTemplateTheme.light,
    this.isPanMode = false,
    this.onStrokeStart,
    this.onStrokeEnd,
    this.onUndo,
    this.onRedo,
    this.onStrokeWidthChanged,
    this.strokeSizes = const [2.0, 4.0, 8.0, 16.0, 32.0],
    this.eraserWidth = 30.0,
    this.eraserSizes = const [10.0, 20.0, 30.0, 60.0, 100.0],
    this.onEraserWidthChanged,
    this.onToggleEraser,
    this.multiPage = true,
    this.colors = const [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ],
    this.initialColor = Colors.black,
    this.onColorChanged,
    this.eraserIcon = Icons.clear,
    this.eraserIconSize = 18.0,
    this.eraserActiveColor = Colors.blueAccent,
    this.eraserInactiveColor = Colors.black54,
    this.scrollMode = ScrollMode.continuous,
    this.initialPageIndex = 0,
  });

  @override
  State<PaperCanvas> createState() => PaperCanvasState();
}

class PaperCanvasState extends State<PaperCanvas>
    with SingleTickerProviderStateMixin {
  final List<Stroke> _strokes = [];
  final List<Stroke> _redoStack = [];
  final Map<int, ui.Image> _backgroundImages = {};
  ui.Image? _headerImage;
  ui.Image? _footerImage;
  final Map<int, double> _headerOffsetsY = {};
  final Map<int, List<Stroke>> _pageRedoStacks = {};

  /// Strokes being touched by the eraser. They are temporarily removed from
  /// the cache and drawn with low opacity until the finger is lifted.
  final List<Stroke> _highlightedStrokes = [];

  /// Pre-rendered picture of all committed strokes. Rebuilt once per stroke
  /// finalization (and undo/redo/clear etc.) — blitted cheaply every frame.
  ui.Picture? _cachedPicture;

  // ── Page geometry ──────────────────────────────────────────────────────────
  // Upstream hard-coded A4 as a pair of static constants. Both now come from
  // the widget's page format so a document can be A3, Letter or landscape.

  double get _pageWidth => widget.pageFormat.width;

  double get _pageHeight => widget.pageFormat.height;

  /// In infinite mode there are no page bands: strokes are not clamped, the
  /// surface grows in both axes, and page-index maths is meaningless.
  bool get _isInfinite => widget.canvasMode == CanvasMode.infinite;

  PaperTool get _activeTool =>
      widget.tool ?? (widget.isEraser ? PaperTool.eraser : PaperTool.pen);

  bool get _isErasing => _activeTool == PaperTool.eraser;

  int _getStrokePage(Stroke s) {
    if (s.points.isEmpty || _isInfinite) return 0;
    return (s.points.first.dy / _pageHeight).floor();
  }

  late Color _currentColor;

  Stroke? _currentStroke;
  bool _isSpacePressed = false;
  int _gesturePointerCount = 0; // Explicitly track fingers/pointers
  Offset? _pointerPosition;
  late TransformationController _transformationController;
  AnimationController? _alignmentController;
  Animation<Matrix4>? _alignmentAnimation;
  final FocusNode _focusNode = FocusNode();
  BoxConstraints? _lastConstraints;
  int _pageCount = 1;
  DateTime? _lastMultiTouchTime;
  double _baseScale = 1.0;
  Offset? _lastFocalPoint;
  bool _isInitialResetDone = false;
  late int _currentPageIndex;
  static const Duration _pinchCooldown = Duration(milliseconds: 350);

  // Velocity-based variable-width tracking
  Offset? _lastVelocityPos;
  DateTime? _lastVelocityTime;
  double _smoothedWidth = 0.0;

  // ── Document extent ────────────────────────────────────────────────────────
  // In paged mode the document is exactly as wide as a page and as tall as the
  // page count. In infinite mode it is a large surface that grows outward as
  // drawing approaches its edge, matching the behaviour of a whiteboard.

  /// Recomputed on every cache rebuild rather than per frame -- it is O(number
  /// of strokes) and the extent can only change when the stroke list does.
  Size? _infiniteExtentCache;

  Size get _infiniteExtent {
    final Size? cached = _infiniteExtentCache;
    if (cached != null) return cached;

    // Grow past the drawn content, but never below the configured minimum.
    // The minimum is what makes a fresh canvas feel unbounded; deriving it
    // from the page size (as this once did) made it far too small.
    double maxX = 0;
    double maxY = 0;
    for (final stroke in _strokes) {
      final Rect b = stroke.bounds;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;
    }
    return _infiniteExtentCache = Size(
      math.max(maxX + widget.infiniteCanvasMargin,
          widget.infiniteCanvasMinSize.width),
      math.max(maxY + widget.infiniteCanvasMargin,
          widget.infiniteCanvasMinSize.height),
    );
  }

  double get _documentWidth => _isInfinite ? _infiniteExtent.width : _pageWidth;

  double get _documentHeight =>
      _isInfinite ? _infiniteExtent.height : _pageCount * _pageHeight;

  void addPage() {
    if (!widget.multiPage) {
      return;
    }
    setState(() {
      _pageCount++;
      _currentPageIndex = _pageCount - 1;

      // Reset view to show the new last page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) goToPage(_currentPageIndex);
      });
    });
  }

  void deletePage(int index) {
    if (index < 0 || index >= _pageCount) return;

    final double startY = index * _pageHeight;
    final double endY = (index + 1) * _pageHeight;

    setState(() {
      // 1. Remove strokes that touch this page
      _strokes.removeWhere(
        (stroke) => stroke.points.any((p) => p.dy >= startY && p.dy < endY),
      );

      if (_pageCount == 1) {
        // Special case: Only page exists. Clear contents but keep the page.
        _backgroundImages.remove(index);
        _redoStack.clear();
        _pageRedoStacks.clear();
        _rebuildCache();
      } else {
        // 2. Shift subsequent strokes UP
        for (final stroke in _strokes) {
          if (stroke.points.any((p) => p.dy >= endY)) {
            for (int i = 0; i < stroke.points.length; i++) {
              stroke.points[i] = Offset(
                stroke.points[i].dx,
                stroke.points[i].dy - _pageHeight,
              );
            }
          }
        }

        // 3. Re-index backgrounds
        final newBackgrounds = <int, ui.Image>{};
        _backgroundImages.forEach((idx, img) {
          if (idx < index) {
            newBackgrounds[idx] = img;
          } else if (idx > index) {
            newBackgrounds[idx - 1] = img;
          }
        });
        _backgroundImages.clear();
        _backgroundImages.addAll(newBackgrounds);

        // 3b. Re-index page redo stacks
        final newRedoStacks = <int, List<Stroke>>{};
        _pageRedoStacks.forEach((idx, stack) {
          if (idx < index) {
            newRedoStacks[idx] = stack;
          } else if (idx > index) {
            newRedoStacks[idx - 1] = stack;
          }
        });
        _pageRedoStacks.clear();
        _pageRedoStacks.addAll(newRedoStacks);

        // 4. Update page count
        _pageCount--;

        if (_currentPageIndex >= _pageCount) {
          _currentPageIndex = _pageCount - 1;
        }

        // Destructive operation: clear redo
        _redoStack.clear();
        _rebuildCache();

        // Snap back to current page
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) goToPage(_currentPageIndex);
        });
      }
    });

    widget.onStrokeEnd?.call(); // Trigger external updates if any
  }

  void insertPage(int index) {
    if (!widget.multiPage) return;
    final double insertY = index * _pageHeight;

    setState(() {
      // 1. Shift existing strokes DOWN from the insertion point
      for (final stroke in _strokes) {
        if (stroke.points.any((p) => p.dy >= insertY)) {
          for (int i = 0; i < stroke.points.length; i++) {
            stroke.points[i] = Offset(
              stroke.points[i].dx,
              stroke.points[i].dy + _pageHeight,
            );
          }
        }
      }

      // 2. Shift backgrounds DOWN
      final newBackgrounds = <int, ui.Image>{};
      _backgroundImages.forEach((idx, img) {
        if (idx < index) {
          newBackgrounds[idx] = img;
        } else {
          newBackgrounds[idx + 1] = img;
        }
      });
      _backgroundImages.clear();
      _backgroundImages.addAll(newBackgrounds);

      // 2b. Shift page redo stacks DOWN
      final newRedoStacks = <int, List<Stroke>>{};
      _pageRedoStacks.forEach((idx, stack) {
        if (idx < index) {
          newRedoStacks[idx] = stack;
        } else {
          newRedoStacks[idx + 1] = stack;
        }
      });
      _pageRedoStacks.clear();
      _pageRedoStacks.addAll(newRedoStacks);

      // 3. Update page count
      _pageCount++;

      // Destructive operation: clear redo
      _redoStack.clear();
      _rebuildCache();

      // Navigate to the newly inserted page
      _currentPageIndex = index;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) goToPage(_currentPageIndex);
      });
    });

    widget.onStrokeEnd?.call();
  }

  Future<void> setBackgroundImage(
    int pageIndex,
    Uint8List bytes, {
    bool clearOthers = false,
  }) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    setState(() {
      if (clearOthers) _backgroundImages.clear();
      _backgroundImages[pageIndex] = frameInfo.image;
      if (pageIndex >= _pageCount) {
        _pageCount = pageIndex + 1;
      }
    });
  }

  /// Sets a network image as the background for a specific page.
  Future<void> setNetworkBackgroundImage(
    int pageIndex,
    String url, {
    bool clearOthers = false,
  }) async {
    try {
      final Uri uri = Uri.parse(url.trim());
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();

      if (response.statusCode == 200) {
        final Uint8List bytes = await consolidateHttpClientResponseBytes(
          response,
        );
        try {
          await setBackgroundImage(pageIndex, bytes, clearOthers: clearOthers);
        } catch (e) {
          // Handler
        }
      }
    } catch (e) {
      // Handler
    }
  }

  /// Sets a local image as the header for all pages.
  Future<void> setHeaderImage(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      setState(() {
        _headerImage = frameInfo.image;
      });
    } catch (e) {
      // Handler
    }
  }

  /// Sets a network image as the header for all pages.
  Future<void> setNetworkHeaderImage(String url) async {
    try {
      final Uri uri = Uri.parse(url.trim());
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();

      if (response.statusCode == 200) {
        final Uint8List bytes = await consolidateHttpClientResponseBytes(
          response,
        );
        try {
          await setHeaderImage(bytes);
        } catch (e) {
          // Handler
        }
      }
    } catch (e) {
      // Handler
    }
  }

  /// Sets a local image as the footer for all pages.
  Future<void> setFooterImage(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      setState(() {
        _footerImage = frameInfo.image;
      });
    } catch (e) {
      // Handler
    }
  }

  /// Sets a network image as the footer for all pages.
  Future<void> setNetworkFooterImage(String url) async {
    try {
      final Uri uri = Uri.parse(url.trim());
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();

      if (response.statusCode == 200) {
        final Uint8List bytes = await consolidateHttpClientResponseBytes(
          response,
        );
        try {
          await setFooterImage(bytes);
        } catch (e) {
          // Handler
        }
      }
    } catch (e) {
      // Handler
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    // `color` is the host-driven pen colour; `initialColor` only seeds the
    // built-in palette. Upstream seeded from `initialColor` and then never
    // read `color` again, which left the documented `color` property inert.
    _currentColor = widget.color != const Color(0xFF000000)
        ? widget.color
        : widget.initialColor;
    _currentPageIndex = widget.initialPageIndex;
    _transformationController = TransformationController();

    _alignmentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150), // Snappier but smooth
    )..addListener(() {
        if (_alignmentAnimation != null) {
          _transformationController.value = _alignmentAnimation!.value;
        }
      });

    _transformationController.addListener(_enforceBounds);
  }

  @override
  void didUpdateWidget(PaperCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(this);
    }
    // Adopt a host-driven colour change. Only on an actual change, so that a
    // colour picked from the built-in page header is not clobbered by the next
    // unrelated rebuild.
    if (widget.color != oldWidget.color) {
      _currentColor = widget.color;
    }

    // Changing the sheet size or switching between paged and infinite alters
    // the document's geometry underneath the existing strokes: page indices
    // are derived from y/pageHeight, the cached picture is recorded against
    // the document rect, and the infinite extent is memoised. All of it has to
    // be recomputed, or ink silently lands on the wrong page and the surface
    // keeps the dimensions of the format that was just replaced.
    final bool geometryChanged = oldWidget.pageFormat != widget.pageFormat ||
        oldWidget.canvasMode != widget.canvasMode;

    if (geometryChanged || oldWidget.multiPage != widget.multiPage) {
      if (geometryChanged) {
        _infiniteExtentCache = null;
        _recountPages();
        _rebuildCache();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) resetView();
      });
    }
  }

  /// Re-derives the page count from the ink after the page height changes.
  void _recountPages() {
    if (_isInfinite) {
      _pageCount = 1;
      _currentPageIndex = 0;
      return;
    }
    double maxY = 0;
    for (final stroke in _strokes) {
      for (final p in stroke.points) {
        maxY = math.max(maxY, p.dy);
      }
    }
    _pageCount = math.max(1, (maxY / _pageHeight).ceil());
    _currentPageIndex = _currentPageIndex.clamp(0, _pageCount - 1);
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _alignmentController?.dispose();
    _transformationController.removeListener(_enforceBounds);
    _transformationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double get _currentScale =>
      _transformationController.value.getMaxScaleOnAxis();

  /// Calculates a stroke width that is either the base width (fixed in scene space)
  /// or adaptive (thinner when zoomed in) depending on what is smaller.
  /// This ensures the pen looks "normal" at 1x focus regardless of zooming.
  double _effectiveStrokeWidth(double base) =>
      math.min(base, base / _currentScale);

  void clear() {
    setState(() {
      _strokes.clear();
      _redoStack.clear();
      _pageRedoStacks.clear();
      _currentStroke = null;
      _highlightedStrokes.clear();
      _cachedPicture = null;

      if (_backgroundImages.isEmpty) {
        // Case 1: No background -> Reset to a single fresh page
        _pageCount = 1;
      } else {
        // Find the highest page index that has a background
        int maxBgIndex = 0;
        for (var index in _backgroundImages.keys) {
          if (index > maxBgIndex) maxBgIndex = index;
        }

        if (maxBgIndex == 0) {
          // Case 2: Single background image or 1-page PDF -> Reset to 1 page
          _pageCount = 1;
        } else {
          // Case 3: Multi-page background -> Keep all background pages
          _pageCount = maxBgIndex + 1;
        }
      }
    });

    // Reset the viewport so the user sees the top of the "fresh" Page 1
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) resetView();
    });
  }

  /// Clears all background images and PDF templates.
  void clearBackgrounds() {
    setState(() {
      _backgroundImages.clear();
    });
  }

  /// Rebuilds the [_cachedPicture] from the current [_strokes] list.
  ///
  /// Call this inside every [setState] block that mutates [_strokes].
  /// This runs the full stroke-processing pipeline once and records the
  /// result as a [ui.Picture] (vector, zoom-sharp). Subsequent frames just
  /// replay that picture in O(1) instead of re-processing every stroke.
  void _rebuildCache() {
    _infiniteExtentCache = null;
    if (_strokes.isEmpty) {
      _cachedPicture = null;
      return;
    }
    final recorder = ui.PictureRecorder();
    final cacheCanvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _documentWidth, _documentHeight),
    );
    // saveLayer is required so that eraser strokes (BlendMode.clear) punch
    // through the ink strokes that precede them in the list -- but only then.
    // Erasers remove whole strokes and are never persisted, so the only way
    // one reaches this list is via imported legacy data. Since the layer is
    // bounded by the whole document, skipping it when there is nothing to
    // erase avoids an offscreen buffer the size of the canvas, which matters
    // once that canvas is measured in tens of thousands of points.
    final bool needsEraserLayer = _strokes.any((s) => s.isEraser);
    if (needsEraserLayer) {
      cacheCanvas.saveLayer(
        Rect.fromLTWH(0, 0, _documentWidth, _documentHeight),
        Paint(),
      );
    }
    for (final stroke in _strokes) {
      StrokeRendererUtil.drawStroke(cacheCanvas, stroke);
    }
    if (needsEraserLayer) cacheCanvas.restore();
    _cachedPicture = recorder.endRecording();
  }

  void _manualZoom(double zoomFactor, {Offset? focalPoint}) {
    if (_lastConstraints == null) return;

    final Matrix4 matrix = _transformationController.value;
    final double currentScale = matrix.getMaxScaleOnAxis();

    double newScale = currentScale * zoomFactor;
    newScale = newScale.clamp(0.5, 5.0);

    if (newScale == currentScale) return;

    final double effectiveFactor = newScale / currentScale;

    // Zoom center
    final double centerX = focalPoint?.dx ?? _lastConstraints!.maxWidth / 2;
    final double centerY = focalPoint?.dy ?? _lastConstraints!.maxHeight / 2;

    final Matrix4 targetMatrix = Matrix4.identity()
      ..translateByDouble(centerX, centerY, 0.0, 1.0)
      ..scaleByDouble(effectiveFactor, effectiveFactor, effectiveFactor, 1.0)
      ..translateByDouble(-centerX, -centerY, 0.0, 1.0)
      ..multiply(matrix);

    _animateToMatrix(_getConstrainedMatrix(targetMatrix));
  }

  void _animateToMatrix(Matrix4 targetMatrix) {
    _alignmentController?.stop();
    _alignmentAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(
        parent: _alignmentController!,
        curve: Curves.easeOutCubic,
      ),
    );
    _alignmentController!.forward(from: 0.0);
  }

  bool get canUndo => _strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undoPage(int pageIndex) {
    setState(() {
      final int lastIndex = _strokes.lastIndexWhere(
        (s) => _getStrokePage(s) == pageIndex,
      );
      if (lastIndex != -1) {
        final stroke = _strokes.removeAt(lastIndex);
        _pageRedoStacks.putIfAbsent(pageIndex, () => []).add(stroke);
      }
      _rebuildCache();
    });
    widget.onUndo?.call();
  }

  void redoPage(int pageIndex) {
    setState(() {
      final list = _pageRedoStacks[pageIndex];
      if (list != null && list.isNotEmpty) {
        _strokes.add(list.removeLast());
      }
      _rebuildCache();
    });
    widget.onRedo?.call();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      final Stroke lastStroke = _strokes.removeLast();
      _redoStack.add(lastStroke);
      _rebuildCache();
    });
    widget.onUndo?.call();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      final Stroke stroke = _redoStack.removeLast();
      _strokes.add(stroke);
      _rebuildCache();
    });
    widget.onRedo?.call();
  }

  void goToPage(int index) {
    if (index < 0 || index >= _pageCount) return;

    setState(() {
      _currentPageIndex = index;
    });

    if (_lastConstraints == null) return;

    final double screenWidth = _lastConstraints!.maxWidth;
    final double screenHeight = _lastConstraints!.maxHeight;
    final double scale = screenHeight < _pageHeight
        ? screenHeight / _pageHeight
        : math.min(screenWidth / _pageWidth, screenHeight / _pageHeight);

    final double horizontalOffset = (screenWidth - (_pageWidth * scale)) / 2;
    final double verticalOffset = -(index * _pageHeight * scale);

    final Matrix4 targetMatrix = Matrix4.identity()
      ..translateByDouble(horizontalOffset, verticalOffset, 0.0, 1.0)
      ..scaleByDouble(scale, scale, scale, 1.0);

    _animateToMatrix(targetMatrix);
  }

  void _finalizeStroke() {
    if (_currentStroke == null || _currentStroke!.points.isEmpty) return;

    // GHOST PROTECTION: If it's a 1-point stroke (a dot) AND we are in a pinch cooldown,
    // it's likely an accidental touch at the start/end of a gesture.
    if (_currentStroke!.points.length == 1 && _lastMultiTouchTime != null) {
      if (DateTime.now().difference(_lastMultiTouchTime!) < _pinchCooldown) {
        setState(() {
          _currentStroke = null;
          _pointerPosition = null;
        });
        return;
      }
    }

    // Parallel filtering of points and widths to maintain 1-to-1 relationship.
    //
    // Two cases opt out of the page-bounds filter: an infinite canvas has no
    // bounds to fall outside of, and a shape is defined by exactly two anchors
    // -- dropping either would silently resize it rather than trim it.
    final List<Offset> points = [];
    final List<double> widths = [];
    final bool skipBoundsFilter = _isInfinite || _currentStroke!.tool.isShape;

    for (int i = 0; i < _currentStroke!.points.length; i++) {
      final p = _currentStroke!.points[i];
      final bool keep = skipBoundsFilter ||
          (p.dx >= 0.0 &&
              p.dx <= _pageWidth &&
              p.dy >= 0.0 &&
              p.dy <= _documentHeight);
      if (keep) {
        points.add(p);
        if (i < _currentStroke!.widths.length) {
          widths.add(_currentStroke!.widths[i]);
        }
      }
    }

    // A shape needs both anchors; a tap that never dragged is not a shape.
    final bool degenerateShape =
        _currentStroke!.tool.isShape && points.length < 2;

    if (points.isEmpty || degenerateShape) {
      setState(() {
        _currentStroke = null;
        _pointerPosition = null;
      });
      return;
    }

    final Stroke finalStroke = Stroke(
      points: points,
      widths: widths,
      color: _currentStroke!.color,
      strokeWidth: _currentStroke!.strokeWidth,
      tool: _currentStroke!.tool,
    );

    widget.onStrokeEnd?.call();
    setState(() {
      if (!finalStroke.isEraser) {
        _strokes.add(finalStroke);
      }
      _currentStroke = null;
      _pointerPosition = null;

      // If we just finished an eraser gesture, clear the selection and redo stacks
      if (finalStroke.isEraser) {
        if (_highlightedStrokes.isNotEmpty) {
          _highlightedStrokes.clear();
          _redoStack.clear();
          _pageRedoStacks.clear();
          _rebuildCache();
        }
      } else {
        _redoStack.clear();
        _rebuildCache();
      }
    });
  }

  void resetView() {
    if (_lastConstraints == null) return;

    setState(() {
      final double screenWidth = _lastConstraints!.maxWidth;
      final double screenHeight = _lastConstraints!.maxHeight;

      // Primary: scale so the page fills the screen height (great for mobile/tablet).
      // Fallback: if the screen is wider than the A4 page at 1x, scale by width instead.
      final double scaleToFitHeight = screenHeight / _pageHeight;
      final double scaleToFitWidth = screenWidth / _pageWidth;

      // On short screens (mobile/tablet): fill height, allow horizontal centering.
      // On wide screens (desktop): constrain by whichever fits both axes.
      final double scale = screenHeight < _pageHeight
          ? scaleToFitHeight
          : math.min(scaleToFitWidth, scaleToFitHeight);

      // Center the scaled page horizontally
      final double horizontalOffset = (screenWidth - (_pageWidth * scale)) / 2;

      final double verticalOffset = widget.scrollMode == ScrollMode.discrete
          ? -(_currentPageIndex * _pageHeight * scale)
          : 0.0;

      _transformationController.value = Matrix4.identity()
        ..translateByDouble(horizontalOffset, verticalOffset, 0.0, 1.0)
        ..scaleByDouble(scale, scale, scale, 1.0);
    });
  }

  Matrix4 _getConstrainedMatrix(Matrix4 matrix) {
    if (_lastConstraints == null) return matrix;

    final double scale = matrix.getMaxScaleOnAxis();
    final double screenWidth = _lastConstraints!.maxWidth;
    final double screenHeight = _lastConstraints!.maxHeight;

    final double scaledWidth = _pageWidth * scale;
    final double scaledHeight = _documentHeight * scale;

    final translation = matrix.getTranslation();
    double newX = translation.x;
    double newY = translation.y;

    // 1. Horizontal constraint
    if (scaledWidth <= screenWidth) {
      newX = (screenWidth - scaledWidth) / 2;
    } else {
      newX = newX.clamp(screenWidth - scaledWidth, 0.0);
    }

    // 2. Vertical constraint
    if (widget.scrollMode == ScrollMode.discrete) {
      final double pageTopY = _currentPageIndex * _pageHeight * scale;
      final double pageBottomY = (_currentPageIndex + 1) * _pageHeight * scale;
      final double pageHeight = _pageHeight * scale;

      if (pageHeight <= screenHeight) {
        newY = -pageTopY;
      } else {
        newY = newY.clamp(screenHeight - pageBottomY, -pageTopY);
      }
    } else {
      if (scaledHeight <= screenHeight) {
        newY = 0; // Top-Center alignment
      } else {
        newY = newY.clamp(screenHeight - scaledHeight, 0.0);
      }
    }

    final Matrix4 constrained = matrix.clone();
    constrained.setTranslationRaw(newX, newY, 0.0);
    return constrained;
  }

  void _enforceBounds() {
    if (_lastConstraints == null) return;

    // During active gesture or animation, we let the external logic handle it
    if (_gesturePointerCount > 0 ||
        (_alignmentController?.isAnimating ?? false)) {
      return;
    }

    final Matrix4 currentMatrix = _transformationController.value;
    final Matrix4 constrainedMatrix = _getConstrainedMatrix(currentMatrix);

    if (currentMatrix != constrainedMatrix) {
      // Snap only if substantially different to avoid jitter from rounding
      final double dx = (currentMatrix.getTranslation().x -
              constrainedMatrix.getTranslation().x)
          .abs();
      final double dy = (currentMatrix.getTranslation().y -
              constrainedMatrix.getTranslation().y)
          .abs();

      if (dx > 0.5 || dy > 0.5) {
        if (_gesturePointerCount > 0) {
          // Snap during active gesture
          _transformationController.removeListener(_enforceBounds);
          _transformationController.value = constrainedMatrix;
          _transformationController.addListener(_enforceBounds);
        } else {
          // Smooth transition after gesture ends
          _animateToMatrix(constrainedMatrix);
        }
      }
    }
  }

  /// Union of every committed stroke's bounds, or null when nothing is drawn.
  Rect? _contentBounds() {
    Rect? bounds;
    for (final stroke in _strokes) {
      if (stroke.points.isEmpty) continue;
      bounds = bounds == null
          ? stroke.bounds
          : bounds.expandToInclude(stroke.bounds);
    }
    return bounds;
  }

  /// Replays the committed strokes into a PDF page through [t].
  ///
  /// This mirrors StrokeRendererUtil.drawStroke: variable-width ink becomes a
  /// filled envelope, shapes become constant-width outlines. Keeping the two
  /// in step is what makes the exported page look like the screen.
  void _paintStrokesToPdf(PdfGraphics graphics, _PdfPageTransform t) {
    for (final stroke in _strokes) {
      if (stroke.points.isEmpty) continue;

      // Erasers normally delete whole strokes and are never persisted, so any
      // eraser reaching here came from imported legacy data, where it was a
      // clear-blend stroke punching a hole in the ink. PDF has no clear blend,
      // so it is painted in the page colour instead -- visually identical on
      // the blank paper such documents were drawn on.
      final PdfColor pdfColor = stroke.isEraser
          ? PdfColor.fromInt(widget.templateTheme.pageColor.toARGB32())
          : PdfColor.fromInt(stroke.color.toARGB32());
      graphics
        ..setStrokeColor(pdfColor)
        ..setFillColor(pdfColor)
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);

      if (stroke.tool.isShape) {
        final List<Offset> pts = stroke.outlinePoints;
        if (pts.length < 2) continue;
        graphics.setLineWidth(t.mapWidth(stroke.strokeWidth));
        graphics.moveTo(t.mapX(pts.first.dx), t.mapY(pts.first.dy));
        for (final p in pts.skip(1)) {
          graphics.lineTo(t.mapX(p.dx), t.mapY(p.dy));
        }
        graphics.strokePath();
        continue;
      }

      // Process the stroke using shared utility (filter + smooth)
      final processed = StrokeRendererUtil.processStroke(
        stroke.points,
        stroke.widths,
      );
      final List<Offset> smoothedPts = processed['points'];
      final List<double> smoothedWts = processed['widths'];

      if (smoothedPts.length < 2) continue;

      if (smoothedWts.isNotEmpty && smoothedWts.length == smoothedPts.length) {
        // VARIABLE-WIDTH RENDERING (INK-LIKE)
        final envelope = StrokeRendererUtil.generateEnvelope(
          smoothedPts,
          smoothedWts,
        );
        final left = envelope['left']!;
        final right = envelope['right']!;

        if (left.isNotEmpty && right.isNotEmpty) {
          graphics.moveTo(t.mapX(left[0].dx), t.mapY(left[0].dy));
          for (var p in left.skip(1)) {
            graphics.lineTo(t.mapX(p.dx), t.mapY(p.dy));
          }
          for (var p in right.reversed) {
            graphics.lineTo(t.mapX(p.dx), t.mapY(p.dy));
          }
          graphics.fillPath();

          // Thin outline for ultra-smoothness (mirroring painter)
          graphics.setLineWidth(t.mapWidth(0.5));
          graphics.moveTo(t.mapX(left[0].dx), t.mapY(left[0].dy));
          for (var p in left.skip(1)) {
            graphics.lineTo(t.mapX(p.dx), t.mapY(p.dy));
          }
          for (var p in right.reversed) {
            graphics.lineTo(t.mapX(p.dx), t.mapY(p.dy));
          }
          graphics.strokePath();
        }
      } else {
        // FIXED-WIDTH RENDERING (Legacy)
        graphics.setLineWidth(t.mapWidth(stroke.strokeWidth));
        bool started = false;
        for (final point in smoothedPts) {
          final py = t.mapY(point.dy);
          if (!started) {
            graphics.moveTo(t.mapX(point.dx), py);
            started = true;
          } else {
            graphics.lineTo(t.mapX(point.dx), py);
          }
        }
        graphics.strokePath();
      }
    }
  }

  /// Builds the export document. Shared by [exportToPdf] and [printPdf] so the
  /// printed page and the shared file can never diverge.
  Future<Uint8List?> buildPdf() async {
    if (_strokes.isEmpty) return null;

    final pdf = pw.Document();
    final PageFormat format = widget.pageFormat;
    final Size pageSize = format.pageSize;

    // Header / footer bitmaps, if the host supplied any.
    Uint8List? headerBytes;
    if (_headerImage != null) {
      final byteData =
          await _headerImage!.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) headerBytes = byteData.buffer.asUint8List();
    }
    Uint8List? footerBytes;
    if (_footerImage != null) {
      final byteData =
          await _footerImage!.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) footerBytes = byteData.buffer.asUint8List();
    }

    final bool isRepeating =
        _backgroundImages.length == 1 && _backgroundImages.containsKey(0);
    Uint8List? repeatingBgBytes;
    if (isRepeating) {
      final byteData = await _backgroundImages[0]!
          .toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) repeatingBgBytes = byteData.buffer.asUint8List();
    }

    List<pw.Widget> decorations(Uint8List? bgBytes) {
      return <pw.Widget>[
        if (bgBytes != null)
          pw.Positioned.fill(
            child: pw.Image(pw.MemoryImage(bgBytes), fit: pw.BoxFit.fill),
          ),
        // Vector ruling, drawn from the same renderer as the on-screen canvas.
        if (widget.template != PaperTemplate.blank)
          PaperTemplateRenderer.pdfWidget(
            template: widget.template,
            pageSize: pageSize,
            theme: widget.templateTheme,
          ),
        if (headerBytes != null)
          pw.Positioned(
            top: 0,
            left: 0,
            right: 0,
            child:
                pw.Image(pw.MemoryImage(headerBytes), fit: pw.BoxFit.contain),
          ),
        if (footerBytes != null)
          pw.Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child:
                pw.Image(pw.MemoryImage(footerBytes), fit: pw.BoxFit.contain),
          ),
      ];
    }

    if (_isInfinite) {
      // An unbounded canvas has no page grid to slice along, so the drawn
      // region is scaled to fit a single sheet -- the same thing exporting a
      // whiteboard anywhere else does. Never scaled up past 1:1, so a small
      // sketch prints at its true size rather than being blown up.
      final Rect? content = _contentBounds();
      if (content == null || content.isEmpty) return null;

      final double margin = pageSize.width * 0.06;
      final double usableW = pageSize.width - margin * 2;
      final double usableH = pageSize.height - margin * 2;
      final double scale = math.min(
        math.min(usableW / content.width, usableH / content.height),
        1.0,
      );

      // Centre whatever slack is left over.
      final double drawnW = content.width * scale;
      final double drawnH = content.height * scale;
      final double padX = (pageSize.width - drawnW) / 2;
      final double padY = (pageSize.height - drawnH) / 2;

      final transform = _PdfPageTransform(
        pageHeight: pageSize.height,
        offsetX: content.left - padX / scale,
        offsetY: content.top - padY / scale,
        scale: scale,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: format.pdfPageFormat,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) => pw.Stack(
            children: <pw.Widget>[
              ...decorations(repeatingBgBytes),
              pw.CustomPaint(
                size: PdfPoint(pageSize.width, pageSize.height),
                painter: (PdfGraphics graphics, PdfPoint _) =>
                    _paintStrokesToPdf(graphics, transform),
              ),
            ],
          ),
        ),
      );

      return pdf.save();
    }

    // Paged mode: one PDF page per canvas page, growing to fit any ink that
    // sits past the last known page.
    double maxY = 0;
    for (final stroke in _strokes) {
      for (final point in stroke.points) {
        maxY = math.max(maxY, point.dy);
      }
    }

    final int actualPageCount = widget.multiPage
        ? math.max(_pageCount, (maxY / pageSize.height).ceil())
        : _pageCount;

    for (int i = 0; i < math.max(1, actualPageCount); i++) {
      final double pageOffset = i * pageSize.height;

      Uint8List? bgBytes;
      if (isRepeating) {
        bgBytes = repeatingBgBytes;
      } else if (_backgroundImages.containsKey(i)) {
        final byteData = await _backgroundImages[i]!
            .toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) bgBytes = byteData.buffer.asUint8List();
      }

      final transform = _PdfPageTransform(
        pageHeight: pageSize.height,
        offsetY: pageOffset,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: format.pdfPageFormat,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) => pw.Stack(
            children: <pw.Widget>[
              ...decorations(bgBytes),
              pw.CustomPaint(
                size: PdfPoint(pageSize.width, pageSize.height),
                painter: (PdfGraphics graphics, PdfPoint _) =>
                    _paintStrokesToPdf(graphics, transform),
              ),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  Future<Uint8List?> exportToPdf({String? fileName, bool share = true}) async {
    final Uint8List? bytes = await buildPdf();
    if (bytes == null) return null;
    if (share) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: fileName ?? 'drawing.pdf',
      );
    }
    return bytes;
  }

  /// Opens the platform print dialog (AirPrint on iOS, the print framework on
  /// Android). Distinct from [exportToPdf], which only offers a share sheet.
  Future<bool> printPdf({String? documentName}) async {
    final Uint8List? bytes = await buildPdf();
    if (bytes == null) return false;
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: documentName ?? 'Drawing',
      format: widget.pageFormat.pdfPageFormat,
    );
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

    // DON'T start ANY interaction here if we are just drawing with a mouse.
    // We handle drawing in the root Listener's _onPointerDown for better control.
    if (details.pointerCount == 1 &&
        !isCtrlPressed &&
        !_isSpacePressed &&
        !widget.isPanMode) {
      return;
    }

    _baseScale = 1.0;
    _lastFocalPoint = details.localFocalPoint;

    if (details.pointerCount > 1 ||
        isCtrlPressed ||
        _isSpacePressed ||
        widget.isPanMode) {
      _lastMultiTouchTime = DateTime.now(); // Navigation detected
    }
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    final bool isNavigating = _isSpacePressed ||
        widget.isPanMode ||
        details.pointerCount > 1 ||
        isCtrlPressed;

    if (isNavigating) {
      // HANDLE CAMERA Transformation manually for perfect control and alignment
      final double deltaScale = details.scale / _baseScale;
      _baseScale = details.scale;

      final Offset focalDelta = details.localFocalPoint -
          (_lastFocalPoint ?? details.localFocalPoint);
      _lastFocalPoint = details.localFocalPoint;

      Matrix4 matrix = _transformationController.value.clone();

      // 1. Zoom (if scale changed)
      if (deltaScale != 1.0) {
        final double currentScale = matrix.getMaxScaleOnAxis();
        final double newScale = (currentScale * deltaScale).clamp(0.5, 5.0);
        final double effectiveFactor = newScale / currentScale;

        final double centerX = details.localFocalPoint.dx;
        final double centerY = details.localFocalPoint.dy;

        matrix = Matrix4.identity()
          ..translateByDouble(centerX, centerY, 0.0, 1.0)
          ..scaleByDouble(
            effectiveFactor,
            effectiveFactor,
            effectiveFactor,
            1.0,
          )
          ..translateByDouble(-centerX, -centerY, 0.0, 1.0)
          ..multiply(matrix);
      }

      // 2. Pan (if position changed or as part of pinch-pan)
      if (focalDelta != Offset.zero) {
        // Translation in IV is in scene coordinates
        final Matrix4 translation = Matrix4.identity()
          ..translateByDouble(focalDelta.dx, focalDelta.dy, 0.0, 1.0);
        matrix = translation * matrix;
      }

      // Apply the constrained matrix
      _transformationController.value = _getConstrainedMatrix(matrix);

      // ANY navigation frame (pinch, pan, zoom) triggers the 'Safety Cooldown'
      _lastMultiTouchTime = DateTime.now();

      // If we are navigating, make sure current stroke is canceled
      if (_currentStroke != null) {
        setState(() {
          _currentStroke = null;
          _pointerPosition = null;
          _highlightedStrokes.clear();
        });
      }
      return;
    }

    final scenePosition = _transformationController.toScene(
      details.localFocalPoint,
    );

    // ERASER PREVIEW logic
    if (_isErasing && _currentStroke != null) {
      bool hit = false;
      // Precision hit-test against all strokes not already highlighted
      for (int i = _strokes.length - 1; i >= 0; i--) {
        if (_strokes[i].isPointNear(scenePosition, widget.eraserWidth / 2)) {
          final stroke = _strokes.removeAt(i);
          _highlightedStrokes.add(stroke);
          hit = true;
        }
      }

      if (hit) {
        setState(() {
          _rebuildCache(); // Hide the newly hit strokes from the background
        });
      }
    }

    // DRAWING logic (Mobile/Trackpad fallback)
    if (_currentStroke != null && !_isErasing) {
      final scenePosition = _transformationController.toScene(
        details.localFocalPoint,
      );

      double? pointWidth;
      if (!_currentStroke!.isEraser) {
        final now = DateTime.now();
        final dt = _lastVelocityTime != null
            ? now.difference(_lastVelocityTime!).inMicroseconds / 1000.0
            : 16.0;
        final dist = _lastVelocityPos != null
            ? (scenePosition - _lastVelocityPos!).distance
            : 0.0;
        final speed = dt > 0 ? dist / dt : 0.0;
        final double base = _currentStroke!.strokeWidth;
        // Faster → wider, slower → narrower. Clamped to [40%, 140%] of base.
        final double targetWidth = (base * (0.4 + speed / 8.0)).clamp(
          base * 0.4,
          base * 1.4,
        );
        // Smoother exponential smoothing (0.15 instead of 0.25)
        _smoothedWidth += (targetWidth - _smoothedWidth) * 0.15;
        pointWidth = _smoothedWidth;
        _lastVelocityPos = scenePosition;
        _lastVelocityTime = now;
      }

      setState(() {
        _pointerPosition = scenePosition;
        _currentStroke?.points.add(scenePosition);
        if (pointWidth != null) _currentStroke?.widths.add(pointWidth);
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _gesturePointerCount++;
    if (_gesturePointerCount > 1) {
      _lastMultiTouchTime = DateTime.now();
      _finalizeStroke(); // Cancel active drawing
      return;
    }

    final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    if (_isSpacePressed || widget.isPanMode || isCtrlPressed) return;

    // Cooldown check
    if (_lastMultiTouchTime != null &&
        DateTime.now().difference(_lastMultiTouchTime!) < _pinchCooldown) {
      return;
    }

    // Strictly ignore points that are OUT of the valid drawing box
    // we allow a tiny 1-pixel margin for "sloppy" clicks at the absolute edge
    if (event.localPosition.dx < -1.0 ||
        event.localPosition.dx > _pageWidth + 1.0 ||
        event.localPosition.dy < -1.0 ||
        event.localPosition.dy > _documentHeight + 1.0) {
      return;
    }

    widget.onStrokeStart?.call();

    // STRICT FILTER: If the starting point is outside the valid area, IGNORE it entirely.
    if (event.localPosition.dx < 0.0 ||
        event.localPosition.dx > _pageWidth ||
        event.localPosition.dy < 0.0 ||
        event.localPosition.dy > _documentHeight) {
      return;
    }

    final scenePosition = event.localPosition;
    final double baseStrokeWidth = _effectiveStrokeWidth(
      _isErasing ? widget.eraserWidth : widget.strokeWidth,
    );

    // Initialise velocity tracking — start thin (pen touch)
    _lastVelocityPos = scenePosition;
    _lastVelocityTime = DateTime.now();
    _smoothedWidth = _isErasing ? baseStrokeWidth : baseStrokeWidth * 0.4;

    setState(() {
      _pointerPosition = scenePosition;
      _currentStroke = Stroke(
        points: [scenePosition],
        widths: _activeTool.isVariableWidth ? [_smoothedWidth] : [],
        color: _isErasing ? Colors.white : _currentColor,
        strokeWidth: baseStrokeWidth,
        tool: _activeTool,
      );

      // Initial hit-test on Down
      if (_isErasing) {
        bool hit = false;
        for (int i = _strokes.length - 1; i >= 0; i--) {
          if (_strokes[i].isPointNear(scenePosition, widget.eraserWidth / 2)) {
            final stroke = _strokes.removeAt(i);
            _highlightedStrokes.add(stroke);
            hit = true;
          }
        }
        if (hit) _rebuildCache();
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Only process points that are within the valid document area.
    // This prevents "gutter strokes" from being recorded when drawing near the edges.
    // An infinite canvas has no gutter, so every point counts.
    final bool isInside = _isInfinite ||
        (event.localPosition.dx >= 0.0 &&
            event.localPosition.dx <= _pageWidth &&
            event.localPosition.dy >= 0.0 &&
            event.localPosition.dy <= _documentHeight);

    if (isInside) {
      _pointerPosition = event.localPosition;
    } else {
      // If outside, we update the hover pointer but don't add to the stroke
      _pointerPosition = event.localPosition;
    }

    if (_currentStroke != null) {
      if (isInside) {
        // ERASER logic
        if (_isErasing) {
          bool hit = false;
          for (int i = _strokes.length - 1; i >= 0; i--) {
            if (_strokes[i]
                .isPointNear(event.localPosition, widget.eraserWidth / 2)) {
              final stroke = _strokes.removeAt(i);
              _highlightedStrokes.add(stroke);
              hit = true;
            }
          }
          if (hit) {
            setState(() {
              _rebuildCache();
            });
          }
        }

        // Compute velocity-based width for non-eraser strokes
        double? pointWidth;
        if (_currentStroke!.tool.isVariableWidth) {
          final now = DateTime.now();
          final dt = _lastVelocityTime != null
              ? now.difference(_lastVelocityTime!).inMicroseconds / 1000.0
              : 16.0;
          final dist = _lastVelocityPos != null
              ? (event.localPosition - _lastVelocityPos!).distance
              : 0.0;
          final speed = dt > 0 ? dist / dt : 0.0; // pixels/ms

          final double base = _currentStroke!.strokeWidth;
          // Faster → wider, slower → narrower. Clamped to [40%, 140%] of base.
          final double targetWidth = (base * (0.4 + speed / 8.0)).clamp(
            base * 0.4,
            base * 1.4,
          );
          // Smoother exponential smoothing (0.15 instead of 0.25)
          _smoothedWidth += (targetWidth - _smoothedWidth) * 0.15;
          pointWidth = _smoothedWidth;

          _lastVelocityPos = event.localPosition;
          _lastVelocityTime = now;
        }

        setState(() {
          final Stroke? stroke = _currentStroke;
          if (stroke == null) return;
          if (stroke.tool.isShape) {
            // A shape is defined by exactly two anchors. Dragging moves the
            // second one; it must not accumulate the whole drag path or the
            // shape would be re-derived from a stale endpoint.
            if (stroke.points.length < 2) {
              stroke.points.add(event.localPosition);
            } else {
              stroke.points[1] = event.localPosition;
            }
            stroke.invalidateGeometry();
          } else {
            stroke.points.add(event.localPosition);
            if (pointWidth != null) stroke.widths.add(pointWidth);
          }
        });
      } else {
        // Diagnostic: if the user is moving FAR outside, let's log it
        if (event.localPosition.dx < -50.0 ||
            event.localPosition.dx > _pageWidth + 50.0 ||
            event.localPosition.dy < -50.0 ||
            event.localPosition.dy > _documentHeight + 50.0) {
          debugPrint(
            '⚠️ Warning: Pointer move FAR out of bounds: ${event.localPosition}',
          );
        }
      }
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_gesturePointerCount > 1) _lastMultiTouchTime = DateTime.now();
    _gesturePointerCount = math.max(0, _gesturePointerCount - 1);

    if (_gesturePointerCount == 0) {
      _finalizeStroke();
    }
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    _finalizeStroke();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (
        PointerSignalEvent resolvedEvent,
      ) {
        if (resolvedEvent is! PointerScrollEvent) return;

        // ANY scroll event (zoom or normal vertical scroll) should trigger the 'Pinch Guard' cooldown
        _lastMultiTouchTime = DateTime.now();

        // If we are currently drawing (shouldn't happen with mouse wheel but might on trackpads), cancel it
        if (_currentStroke != null) {
          setState(() {
            _currentStroke = null;
            _pointerPosition = null;
          });
        }

        final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

        if (isCtrlPressed) {
          // Zoom in/out based on scroll direction
          final double zoomFactor =
              resolvedEvent.scrollDelta.dy < 0 ? 1.2 : 0.8;
          _manualZoom(zoomFactor, focalPoint: resolvedEvent.localPosition);
        } else {
          if (widget.scrollMode == ScrollMode.discrete) return;
          // Normal vertical scroll
          final Matrix4 matrix = _transformationController.value.clone();
          final double scale = matrix.getMaxScaleOnAxis();
          matrix.translateByDouble(
              0.0, -resolvedEvent.scrollDelta.dy / scale, 0.0, 1.0);
          _animateToMatrix(_getConstrainedMatrix(matrix));
        }
      });
    }
  }

  void _onHover(PointerHoverEvent event) {
    if (_isErasing) {
      setState(() {
        _pointerPosition = event.localPosition;
      });
    }
  }

  void _onExit(PointerExitEvent event) {
    if (_isErasing) {
      setState(() {
        _pointerPosition = null;
      });
    }
  }

  /// Returns the current strokes as a single encoded string.
  /// Whether anything has been drawn.
  bool get hasStrokes => _strokes.isNotEmpty;

  /// The number of canvas pages (always 1 for an infinite canvas).
  int get pageCount => _isInfinite ? 1 : _pageCount;

  /// Bounding box of the committed ink, or null if nothing is drawn.
  Rect? get contentBounds => _contentBounds();

  /// The strokes as a list of JSON objects.
  ///
  /// Preferred over [getEncodedData] when the destination stores structured
  /// JSON rather than an opaque blob, since each stroke stays independently
  /// readable on the far end.
  List<Map<String, dynamic>> getStrokesJson() {
    return _strokes.map((Stroke s) => s.toJson()).toList();
  }

  /// Replaces the canvas contents from [getStrokesJson] output.
  ///
  /// Entries that fail to parse are skipped rather than aborting the load, so
  /// one malformed stroke cannot cost the user the rest of the drawing.
  void loadStrokesJson(List<dynamic> json) {
    final List<Stroke> parsed = <Stroke>[];
    for (final entry in json) {
      if (entry is! Map) continue;
      try {
        parsed.add(Stroke.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        continue;
      }
    }

    setState(() {
      _strokes
        ..clear()
        ..addAll(parsed);
      _redoStack.clear();
      _pageRedoStacks.clear();

      if (!_isInfinite) {
        double maxY = 0;
        for (final stroke in _strokes) {
          for (final p in stroke.points) {
            maxY = math.max(maxY, p.dy);
          }
        }
        _pageCount = math.max(1, (maxY / _pageHeight).ceil());
      }

      _rebuildCache();
    });
  }

  /// Rasterises the drawing (with its paper template) for use as a thumbnail.
  ///
  /// Renders the content bounding box rather than the whole surface: on an
  /// infinite canvas the drawn area is usually a small corner of a very large
  /// document, and rasterising all of it would be slow and mostly blank.
  Future<ui.Image?> renderThumbnail({
    double maxDimension = 512,
    double padding = 24,
  }) async {
    final Rect? content = _contentBounds();
    if (content == null || content.isEmpty) return null;

    final Rect area = content.inflate(padding);
    final double scale = math
        .min(maxDimension / area.width, maxDimension / area.height)
        .clamp(0.01, 4.0);
    final int outW = math.max(1, (area.width * scale).round());
    final int outH = math.max(1, (area.height * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..color = widget.templateTheme.pageColor,
    );
    canvas.scale(scale);
    canvas.translate(-area.left, -area.top);

    if (widget.template != PaperTemplate.blank) {
      PaperTemplateRenderer.paintToCanvas(
        canvas: canvas,
        origin: Offset.zero,
        template: widget.template,
        pageSize: Size(_pageWidth, _pageHeight),
        theme: widget.templateTheme,
      );
    }
    for (final stroke in _strokes) {
      StrokeRendererUtil.drawStroke(canvas, stroke);
    }

    return recorder.endRecording().toImage(outW, outH);
  }

  String getEncodedData() {
    return _strokes.map((s) => s.serialize()).join('\n');
  }

  /// Loads strokes from a single encoded string.
  void loadEncodedData(String encodedData) {
    if (encodedData.isEmpty) return;
    final List<String> lines = encodedData.split('\n');

    setState(() {
      _strokes.clear();
      _redoStack.clear();
      _pageRedoStacks.clear();
      double maxY = 0.0;
      for (final data in lines) {
        if (data.trim().isEmpty) continue;
        try {
          final stroke = Stroke.deserialize(data);

          // STRICT FILTER: If any point is significantly beyond current known size, clamp it or ignore it.
          // An infinite canvas is exempt -- clamping there would drag every
          // stroke drawn to the right of the first page back onto it.
          final List<Offset> validPoints = _isInfinite
              ? stroke.points
              : stroke.points
                  .map(
                    (p) => Offset(
                      p.dx.clamp(0.0, _pageWidth),
                      p.dy, // We calculate maxY first to determine pages
                    ),
                  )
                  .toList();

          final cleanStroke = Stroke(
            points: validPoints,
            widths: stroke.widths,
            color: stroke.color,
            strokeWidth: stroke.strokeWidth,
            tool: stroke.tool,
          );

          _strokes.add(cleanStroke);
          for (final p in validPoints) {
            if (p.dy > maxY) maxY = p.dy;
          }
        } catch (e) {
          debugPrint('Error deserializing stroke: $e');
        }
      }

      if (maxY > 0) {
        // Use a much more robust 20.0 pixel margin for mobile to skip accidental slips below the boundary
        final int requiredPages = ((maxY - 20.0) / _pageHeight).floor() + 1;
        if (requiredPages > _pageCount) {
          _pageCount = requiredPages;
          debugPrint(
            '📄 AUTO-EXPANDED PAGES: New Count = $_pageCount (based on maxY = $maxY)',
          );
        }
      }
      _rebuildCache();
    });
  }

  /// Returns the current strokes in the legacy Base64-encoded JSON format.
  String getLegacyEncodedData() {
    const double legacyWidth = 714.0;
    const double legacyHeight = 1136.7;
    final double scaleX = legacyWidth / _pageWidth;
    final double scaleY = legacyHeight / _pageHeight;

    // Partition strokes into pages
    final List<List<Stroke>> strokesPerPage = List.generate(
      _pageCount,
      (_) => [],
    );
    for (final stroke in _strokes) {
      final int page = _getStrokePage(stroke).clamp(0, _pageCount - 1);
      final double yOffset = page * _pageHeight;

      final scaledPoints = stroke.points
          .map((p) => Offset(p.dx * scaleX, (p.dy - yOffset) * scaleY))
          .toList();

      strokesPerPage[page].add(
        Stroke(
          points: scaledPoints,
          widths: stroke.widths.isNotEmpty
              ? stroke.widths.map((w) => w * math.min(scaleX, scaleY)).toList()
              : [],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth * math.min(scaleX, scaleY),
          tool: stroke.tool,
        ),
      );
    }

    final List<Map<String, dynamic>> pagesJson = strokesPerPage
        .map((strokes) => {'strokes': strokes.map((s) => s.toJson()).toList()})
        .toList();

    final Map<String, dynamic> data = {
      'canvasWidth': legacyWidth,
      'canvasHeight': legacyHeight,
      'pages': pagesJson,
    };

    final String jsonString = jsonEncode(data);
    final List<int> byteData = utf8.encode(jsonString);
    return base64Encode(Uint8List.fromList(byteData));
  }

  /// Loads strokes from the legacy Base64-encoded JSON format.
  void loadLegacyEncodedData(String encodedData) {
    if (encodedData.isEmpty) return;

    try {
      final Uint8List byteData = base64Decode(encodedData);
      final String jsonString = utf8.decode(byteData);
      final Map<String, dynamic> strokesData = jsonDecode(jsonString);

      final double refWidth =
          (strokesData['canvasWidth'] as num?)?.toDouble() ?? 595.27 * 1.2;
      final double refHeight =
          (strokesData['canvasHeight'] as num?)?.toDouble() ?? 841.89 * 1.35;
      final List<dynamic> pagesData = strokesData['pages'] as List<dynamic>;

      final double scaleX = _pageWidth / refWidth;
      final double scaleY = _pageHeight / refHeight;

      setState(() {
        _strokes.clear();
        _redoStack.clear();
        _pageRedoStacks.clear();
        _pageCount = pagesData.isNotEmpty ? pagesData.length : 1;

        for (int i = 0; i < pagesData.length; i++) {
          final pageData = pagesData[i] as Map<String, dynamic>;
          final double yOffset = i * _pageHeight;
          final List<dynamic> pageStrokesJson =
              pageData['strokes'] as List<dynamic>;

          for (final strokeJson in pageStrokesJson) {
            final Stroke stroke = Stroke.fromJson(
              strokeJson as Map<String, dynamic>,
            );
            final scaledPoints = stroke.points
                .map((p) => Offset(p.dx * scaleX, (p.dy * scaleY) + yOffset))
                .toList();

            _strokes.add(
              Stroke(
                points: scaledPoints,
                widths: stroke.widths.isNotEmpty
                    ? stroke.widths
                        .map((w) => w * math.min(scaleX, scaleY))
                        .toList()
                    : [],
                color: stroke.color,
                strokeWidth: stroke.strokeWidth * math.min(scaleX, scaleY),
                tool: stroke.tool,
              ),
            );
          }
        }
        _rebuildCache();
      });
    } catch (e) {
      debugPrint('Error loading legacy encoded data: $e');
    }
  }

  /// Unified loader that automatically detects if the data is in Modern or Legacy format.
  void loadData(String data) {
    if (data.isEmpty) return;

    // Check if it's Legacy Format (Base64 JSON)
    bool isLegacy = false;
    try {
      // Base64 strings for JSON objects often start with 'ey' ({})
      if (data.length > 4) {
        final decoded = utf8.decode(base64Decode(data));
        if (decoded.trim().startsWith('{')) {
          isLegacy = true;
        }
      }
    } catch (_) {
      isLegacy = false;
    }

    if (isLegacy) {
      loadLegacyEncodedData(data);
    } else {
      loadEncodedData(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastConstraints = constraints;

        // Auto-initialize view once we have valid, non-zero constraints
        if (!_isInitialResetDone &&
            constraints.maxWidth > 0 &&
            constraints.maxHeight > 0) {
          _isInitialResetDone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) resetView();
          });
        }

        return KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (event) {
            if (event.logicalKey == LogicalKeyboardKey.space) {
              setState(() {
                _isSpacePressed =
                    event is KeyDownEvent || event is KeyRepeatEvent;
              });
            }

            // Handle Ctrl + Key for Zoom (Fallback)
            if (event is KeyDownEvent &&
                HardwareKeyboard.instance.isControlPressed) {
              if (event.logicalKey == LogicalKeyboardKey.equal ||
                  event.logicalKey == LogicalKeyboardKey.add) {
                _manualZoom(1.1); // Zoom In
              } else if (event.logicalKey == LogicalKeyboardKey.minus) {
                _manualZoom(0.9); // Zoom Out
              } else if (event.logicalKey == LogicalKeyboardKey.digit0) {
                resetView(); // Reset Zoom
              } else if (event.logicalKey == LogicalKeyboardKey.keyZ) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  redo(); // Ctrl + Shift + Z
                } else {
                  undo(); // Ctrl + Z
                }
              } else if (event.logicalKey == LogicalKeyboardKey.keyY) {
                redo(); // Ctrl + Y
              }
            }
          },
          autofocus: true,
          child: Focus(
            onFocusChange: (focused) {
              if (!focused) setState(() => _isSpacePressed = false);
            },
            child: Stack(
              children: [
                InteractiveViewer(
                  trackpadScrollCausesScale: false,
                  transformationController: _transformationController,
                  panEnabled: false, // Disable built-in pan to use manual logic
                  scaleEnabled:
                      false, // Disable built-in scale to use manual logic
                  minScale: 0.5,
                  maxScale: 5.0,
                  constrained: false, // Infinite feel
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  onInteractionStart: _handleInteractionStart,
                  onInteractionUpdate: _handleInteractionUpdate,
                  onInteractionEnd: _handleInteractionEnd,
                  child: Listener(
                    onPointerSignal: _handlePointerSignal,
                    child: MouseRegion(
                      onHover: _onHover,
                      onExit: _onExit,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Listener(
                            onPointerDown: _onPointerDown,
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            onPointerCancel: _onPointerUp,
                            behavior: HitTestBehavior.opaque,
                            child: CustomPaint(
                              size: Size(_documentWidth, _documentHeight),
                              painter: PaperPainter(
                                cachedPicture: _cachedPicture,
                                currentStroke: _currentStroke,
                                highlightedStrokes: _highlightedStrokes,
                                eraserPosition:
                                    _isErasing ? _pointerPosition : null,
                                eraserRadius: _isErasing
                                    ? (widget.eraserWidth / 2)
                                    : null,
                                pageWidth: _pageWidth,
                                pageHeight: _pageHeight,
                                backgroundImages: _backgroundImages,
                                headerImage: _headerImage,
                                footerImage: _footerImage,
                                template: widget.template,
                                templateTheme: widget.templateTheme,
                                isInfinite: _isInfinite,
                              ),
                            ),
                          ),
                          // Contextual Page Headers
                          for (int i = 0; i < _pageCount; i++)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (i * _pageHeight) +
                                  (_headerOffsetsY[i] ?? 0.0),
                              child: PageHeader(
                                pageIndex: i,
                                isMultiPage: widget.multiPage,
                                isLastPage: i == _pageCount - 1,
                                canUndo: _strokes.any(
                                  (s) => _getStrokePage(s) == i,
                                ),
                                canRedo:
                                    _pageRedoStacks[i]?.isNotEmpty ?? false,
                                onUndo: () => undoPage(i),
                                onRedo: () => redoPage(i),
                                onInsert: () => insertPage(i),
                                onDelete: () => _showDeleteConfirmation(i),
                                onAddPage: widget.multiPage ? addPage : null,
                                strokeWidth: widget.strokeWidth,
                                strokeSizes: widget.strokeSizes,
                                onStrokeWidthChanged: (width) =>
                                    widget.onStrokeWidthChanged?.call(width),
                                isEraser: _isErasing,
                                eraserWidth: widget.eraserWidth,
                                eraserSizes: widget.eraserSizes,
                                onEraserWidthChanged: (width) =>
                                    widget.onEraserWidthChanged?.call(width),
                                onToggleEraser: (val) =>
                                    widget.onToggleEraser?.call(val),
                                color: _currentColor,
                                colors: widget.colors,
                                onColorChanged: (color) {
                                  setState(() => _currentColor = color);
                                  widget.onColorChanged?.call(color);
                                },
                                eraserIcon: widget.eraserIcon,
                                eraserIconSize: widget.eraserIconSize,
                                eraserActiveColor: widget.eraserActiveColor,
                                eraserInactiveColor: widget.eraserInactiveColor,
                                onDragUpdate: (dy) {
                                  setState(() {
                                    _headerOffsetsY[i] =
                                        (_headerOffsetsY[i] ?? 0.0) + dy;
                                  });
                                },
                                onDragEnd: () {
                                  setState(() {
                                    final currentY = _headerOffsetsY[i] ?? 0.0;
                                    final bottomSnap = _pageHeight - 100.0;
                                    if (currentY > _pageHeight / 2) {
                                      _headerOffsetsY[i] = bottomSnap;
                                    } else {
                                      _headerOffsetsY[i] = 0.0;
                                    }
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!widget.isPanMode &&
                    widget.scrollMode == ScrollMode.continuous)
                  AnimatedBuilder(
                    animation: _transformationController,
                    builder: (context, child) {
                      final matrix = _transformationController.value;
                      final scale = matrix.getMaxScaleOnAxis();
                      final y = -matrix.getTranslation().y;

                      final screenHeight =
                          _lastConstraints?.maxHeight ?? 1000.0;
                      final maxScroll =
                          (_documentHeight * scale) - screenHeight;

                      double progress = 0.0;
                      if (maxScroll > 0) {
                        progress = (y / maxScroll).clamp(0.0, 1.0);
                      }

                      final double maxTop = math.max(0.0, screenHeight - 56.0);
                      final double topOffset = progress * maxTop;

                      return Positioned(
                        right: 0,
                        top: topOffset,
                        child: child!,
                      );
                    },
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        final matrix = _transformationController.value.clone();
                        final scale = matrix.getMaxScaleOnAxis();
                        final screenHeight =
                            _lastConstraints?.maxHeight ?? 1000.0;
                        final maxTop = math.max(0.0, screenHeight - 56.0);
                        final maxScroll =
                            (_documentHeight * scale) - screenHeight;

                        if (maxTop <= 0 || maxScroll <= 0) return;

                        final double progressDelta = details.delta.dy / maxTop;
                        matrix.translateByDouble(
                          0.0,
                          -(progressDelta * maxScroll / scale),
                          0.0,
                          1.0,
                        ); // account for InteractiveViewer scaling the translation

                        _transformationController.value = matrix;
                      },
                      child: Container(
                        width: 32,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(28),
                            bottomLeft: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(-2, 0),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.expand_less,
                              color: Colors.black,
                              size: 20,
                            ),
                            Icon(
                              Icons.expand_more,
                              color: Colors.black,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (widget.scrollMode == ScrollMode.discrete)
                  _buildVerticalNavigation(),
              ], // end Stack children
            ), // end Stack
          ), // end Focus
        ); // end KeyboardListener
      },
    ); // end LayoutBuilder
  }

  Widget _buildVerticalNavigation() {
    if (_pageCount <= 1) return const SizedBox.shrink();

    return Positioned(
      left: 12,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(1, 0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous Page (Up)
              _NavButton(
                icon: Icons.expand_less,
                onPressed: _currentPageIndex > 0
                    ? () => goToPage(_currentPageIndex - 1)
                    : null,
                label: 'Previous',
                size: 24,
              ),
              const SizedBox(height: 4),
              // Next Page (Down)
              _NavButton(
                icon: Icons.expand_more,
                onPressed: _currentPageIndex < _pageCount - 1
                    ? () => goToPage(_currentPageIndex + 1)
                    : null,
                label: 'Next',
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Page?'),
        content: Text(
          'Are you sure you want to delete Page ${index + 1}? All drawing and backgrounds on this page will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              deletePage(index);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String label;
  final double size;

  const _NavButton({
    required this.icon,
    this.onPressed,
    required this.label,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Opacity(
          opacity: isDisabled ? 0.3 : 1.0,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.black87,
              size: size * 0.7,
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps document coordinates onto a PDF page.
///
/// PDF space puts the origin at the bottom-left with y growing upward, so
/// every y is flipped against the page height. In paged mode this is a pure
/// translation by the page offset; in infinite mode it also scales the drawn
/// region down to fit a single sheet.
class _PdfPageTransform {
  const _PdfPageTransform({
    required this.pageHeight,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
  });

  final double pageHeight;
  final double offsetX;
  final double offsetY;
  final double scale;

  double mapX(double x) => (x - offsetX) * scale;

  double mapY(double y) => pageHeight - ((y - offsetY) * scale);

  /// Line widths have to shrink with the drawing, or a scaled-down sketch
  /// would print with implausibly heavy ink.
  double mapWidth(double w) => w * scale;
}
