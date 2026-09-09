import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/page_config.dart';
import '../models/stroke.dart';
import '../utils/stroke_renderer_util.dart';
import 'template_painter.dart';

class PaperPainter extends CustomPainter {
  /// Pre-rendered picture of all committed strokes. Built once per stroke
  /// finalization and blitted cheaply each frame.
  final ui.Picture? cachedPicture;

  /// The stroke currently being drawn (nil when idle). Rendered live each frame.
  final Stroke? currentStroke;

  /// Strokes that are touched by the eraser but not yet deleted.
  /// Rendered with lower opacity for visual feedback.
  final List<Stroke>? highlightedStrokes;

  final Offset? eraserPosition;
  final double? eraserRadius;
  final double? pageWidth;
  final double? pageHeight;
  final Map<int, ui.Image>? backgroundImages;
  final ui.Image? headerImage;
  final ui.Image? footerImage;

  /// Ruling drawn beneath the ink.
  final PaperTemplate template;

  /// Colours and metrics for that ruling.
  final PaperTemplateTheme templateTheme;

  /// Suppresses page-edge decoration when the surface is unbounded.
  final bool isInfinite;

  PaperPainter({
    this.cachedPicture,
    this.currentStroke,
    this.highlightedStrokes,
    this.eraserPosition,
    this.eraserRadius,
    this.pageWidth,
    this.pageHeight,
    this.backgroundImages,
    this.headerImage,
    this.footerImage,
    this.template = PaperTemplate.blank,
    this.templateTheme = PaperTemplateTheme.light,
    this.isInfinite = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background ─────────────────────────────────────────────────────────────
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = templateTheme.pageColor,
    );

    // ── Paper template ─────────────────────────────────────────────────────────
    // Drawn as vectors rather than a tiled bitmap so it stays crisp at any
    // zoom and matches the exported PDF exactly (both go through
    // PaperTemplateRenderer).
    if (template != PaperTemplate.blank &&
        pageWidth != null &&
        pageHeight != null) {
      if (isInfinite) {
        // No pages to align to: tile the ruling across the whole surface.
        final int cols = (size.width / pageWidth!).ceil();
        final int rows = (size.height / pageHeight!).ceil();
        for (int c = 0; c < cols; c++) {
          for (int r = 0; r < rows; r++) {
            PaperTemplateRenderer.paintToCanvas(
              canvas: canvas,
              origin: Offset(c * pageWidth!, r * pageHeight!),
              template: template,
              pageSize: Size(pageWidth!, pageHeight!),
              theme: templateTheme,
            );
          }
        }
      } else {
        final int pageCount = (size.height / pageHeight!).ceil();
        for (int i = 0; i < pageCount; i++) {
          PaperTemplateRenderer.paintToCanvas(
            canvas: canvas,
            origin: Offset(0, i * pageHeight!),
            template: template,
            pageSize: Size(pageWidth!, pageHeight!),
            theme: templateTheme,
          );
        }
      }
    }

    // ── Page boundaries ────────────────────────────────────────────────────────
    // An infinite canvas has no page edges to draw.
    if (pageWidth != null && pageHeight != null && !isInfinite) {
      final boundaryPaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawLine(Offset.zero, Offset(0, size.height), boundaryPaint);
      canvas.drawLine(
        Offset(pageWidth!, 0),
        Offset(pageWidth!, size.height),
        boundaryPaint,
      );

      for (double y = pageHeight!; y < size.height; y += pageHeight!) {
        canvas.drawLine(Offset(0, y), Offset(pageWidth!, y), boundaryPaint);
      }
    }

    // ── Background images ──────────────────────────────────────────────────────
    if (backgroundImages != null && pageHeight != null && pageWidth != null) {
      if (backgroundImages!.length == 1 && backgroundImages!.containsKey(0)) {
        // Repeating background (page 0 for all pages)
        final image = backgroundImages![0]!;
        final double scale = pageWidth! / image.width;
        final double scaledHeight = image.height * scale;
        final int pageCount = (size.height / pageHeight!).ceil();

        for (int i = 0; i < pageCount; i++) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            Rect.fromLTWH(0, i * pageHeight!, pageWidth!, scaledHeight),
            Paint(),
          );
        }
      } else {
        // Per-page background (PDF template)
        backgroundImages!.forEach((pageIndex, image) {
          final double scale = pageWidth! / image.width;
          final double scaledHeight = image.height * scale;
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            Rect.fromLTWH(0, pageIndex * pageHeight!, pageWidth!, scaledHeight),
            Paint(),
          );
        });
      }
    }

    // ── Header & Footer ────────────────────────────────────────────────────────
    if (pageHeight != null && pageWidth != null) {
      final int pageCount = (size.height / pageHeight!).ceil();
      for (int i = 0; i < pageCount; i++) {
        final double yOffset = i * pageHeight!;

        if (headerImage != null) {
          final double hScale = pageWidth! / headerImage!.width;
          final double hHeight = headerImage!.height * hScale;
          canvas.drawImageRect(
            headerImage!,
            Rect.fromLTWH(0, 0, headerImage!.width.toDouble(),
                headerImage!.height.toDouble()),
            Rect.fromLTWH(0, yOffset, pageWidth!, hHeight),
            Paint(),
          );
        }

        if (footerImage != null) {
          final double fScale = pageWidth! / footerImage!.width;
          final double fHeight = footerImage!.height * fScale;
          canvas.drawImageRect(
            footerImage!,
            Rect.fromLTWH(0, 0, footerImage!.width.toDouble(),
                footerImage!.height.toDouble()),
            Rect.fromLTWH(
                0, yOffset + pageHeight! - fHeight, pageWidth!, fHeight),
            Paint(),
          );
        }
      }
    }

    // ── Stroke Rendering ───────────────────────────────────────────────────────
    //
    // The "Ghost" Preview:
    // Any strokes currently being touched by the eraser are drawn with
    // low opacity to signal that they are marked for deletion.
    if (highlightedStrokes != null && highlightedStrokes!.isNotEmpty) {
      for (final stroke in highlightedStrokes!) {
        StrokeRendererUtil.drawStroke(
          canvas,
          stroke.copyWith(
            color: stroke.color.withValues(alpha: 0.3),
          ),
        );
      }
    }

    // The Main Layers:
    // 1. Draw the baked cache (O(1)).
    // 2. Draw the live active stroke (Ink only, erasers are handled by selection logic).
    if (cachedPicture != null) canvas.drawPicture(cachedPicture!);
    if (currentStroke != null) {
      // In Object Eraser mode, we don't draw the currentStroke as a line;
      // we only use it for collision detection. But for Ink, we draw it here.
      if (!currentStroke!.isEraser) {
        StrokeRendererUtil.drawStroke(canvas, currentStroke!);
      }
    }

    // ── Eraser Cursor ──────────────────────────────────────────────────────────
    if (eraserPosition != null && eraserRadius != null) {
      canvas.drawCircle(
        eraserPosition!,
        eraserRadius!,
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        eraserPosition!,
        eraserRadius!,
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) {
    return !identical(oldDelegate.cachedPicture, cachedPicture) ||
        oldDelegate.currentStroke != currentStroke ||
        !identical(oldDelegate.highlightedStrokes, highlightedStrokes) ||
        oldDelegate.eraserPosition != eraserPosition ||
        !identical(oldDelegate.backgroundImages, backgroundImages) ||
        oldDelegate.template != template ||
        oldDelegate.templateTheme != templateTheme ||
        oldDelegate.isInfinite != isInfinite ||
        oldDelegate.pageWidth != pageWidth ||
        oldDelegate.pageHeight != pageHeight;
  }
}
