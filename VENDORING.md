# scribe_canvas (vendored fork)

Forked from [`scribe_canvas` v0.6.3](https://pub.dev/packages/scribe_canvas)
(MIT, © SKS-0212). The upstream `LICENSE` is preserved verbatim.

## Why this is vendored rather than a pub dependency

1. **It could not be depended on.** Upstream declares `sdk: ^3.11.0`; this app
   is pinned by `.fvmrc` to Flutter 3.38.5 / Dart 3.10.4, so `pub get` rejects
   it outright. The source does not actually use any 3.11 feature — the floor
   was simply set high — so the vendored `pubspec.yaml` lowers it.
2. **Every feature we needed required source changes.** Page size was a pair of
   hard-coded A4 constants, there was no template system, and the canvas
   assumed a fixed-width page grid.
3. **There is no upstream repository to fork.** The `homepage` points at a
   GitHub account with no such repo, so the pub archive is the only source of
   truth.

Upstream is at 4 likes / ~30 weekly downloads with an unverified publisher, so
this fork should be treated as owned code, not as a tracked dependency.

## Local changes

| Area | Change |
| --- | --- |
| `models/page_config.dart` | **New.** `ScribePageFormat` (A3/A4/A5/Letter/Legal × portrait/landscape), `ScribeCanvasMode`, `ScribePaperTemplate`, `ScribeTemplateTheme`. |
| `painters/template_painter.dart` | **New.** Vector paper ruling (lined, grid, dots, Cornell) drawn through a sink abstraction so the screen canvas and the PDF share one geometry definition. |
| `models/stroke.dart` | Added `ScribeTool` discriminator and derived `outlinePoints`, so line/rectangle/circle strokes render, hit-test and export from one representation. `isEraser` is now derived from `tool`. Compact serialization gained an optional trailing `tool` field (older data still parses). |
| `widgets/scribe_canvas.dart` | Page geometry comes from `pageFormat` instead of the `a4Width`/`a4Height` constants. Added infinite-canvas mode (no page bands, no x-clamping, auto-growing 2D surface). Added shape-tool input handling. Added `getStrokesJson`/`loadStrokesJson`, `renderThumbnail`, `buildPdf`, `printPdf`. PDF export rewritten for configurable page formats, vector templates and shapes. |
| `painters/scribe_painter.dart` | Renamed `a4Width`/`a4Height` → `pageWidth`/`pageHeight`; draws the paper template; suppresses page edges when infinite. |
| `utils/stroke_renderer_util.dart` | Added `drawShapeOutline`; shapes bypass the freehand smoothing pipeline so corners stay sharp. |
| `widgets/scribe_canvas.dart` (colour) | Upstream seeded `_currentColor` from `initialColor` in `initState` and never read the documented `color` property again, so a host toolbar could not change the pen colour -- only the built-in page header could. `color` is now adopted in `didUpdateWidget`. Covered by `test/host_color_test.dart`. |
| `controllers/scribe_canvas_controller.dart` | Exposed the new state API. Removed `loadPdfBackground`. |
| `pubspec.yaml` | Dropped `pdfx` (only used by `loadPdfBackground`, which we replaced with vector templates) and `file_picker` (declared upstream but never used). Avoids shipping a second PDF engine alongside `syncfusion_flutter_pdfviewer`. |

## Upgrading

There is no upstream git history to merge from. To compare against a newer
release, download the archive and diff:

```sh
curl -sL https://pub.dev/api/archives/scribe_canvas-<version>.tar.gz | tar xz -C /tmp/sc-new
diff -ru /tmp/sc-new/lib packages/scribe_canvas/lib
```
