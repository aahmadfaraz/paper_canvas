# Attribution and provenance

`paper_canvas` is a **derivative work of
[`scribe_canvas` v0.6.3](https://pub.dev/packages/scribe_canvas)** by
**SKS-0212**, used and modified under the MIT License. Credit for the original
canvas engine belongs to that author.

The upstream copyright notice is retained verbatim in [LICENSE](LICENSE), and
upstream's own release history is preserved in
[doc/upstream_scribe_canvas_changelog.md](doc/upstream_scribe_canvas_changelog.md).

## What was inherited from `scribe_canvas`

The foundations of the drawing engine are upstream's work and remain the
backbone of this package:

- The picture-cached rendering strategy — completed strokes are baked into a
  `ui.Picture` so only the active stroke is processed each frame.
- The variable-width ink renderer: velocity-driven stroke width, Catmull-Rom
  smoothing, and the polygon-envelope generator that gives strokes their taper.
- The object eraser (hit-test and remove whole strokes), with per-page and
  global undo/redo stacks.
- The compact delta-encoded stroke serialization format.
- Pointer handling, palm-rejection heuristics, and the pan/zoom navigation
  model including discrete and continuous page scrolling.
- The original vector PDF export approach — drawing strokes through
  `PdfGraphics` rather than rasterising them.

## Why it was forked rather than contributed to

1. **It could not be depended on as published.** Upstream declares
   `sdk: ^3.11.0`, which the toolchain this was first built for did not
   satisfy. The source does not use any 3.11 language feature, so the floor was
   simply set higher than necessary.
2. **The features needed required source changes, not composition.** Paper size
   was a pair of hard-coded A4 constants, there was no template system, and the
   canvas assumed a fixed-width page grid.
3. **There is no public upstream repository.** `homepage` points at a GitHub
   account with no such repo, so the pub archive was the only available source.

Had an upstream repository existed, these changes would have been offered as
pull requests first.

## What this package adds

| Area | Change |
| --- | --- |
| `models/page_config.dart` | **New.** `PageFormat` (A3/A4/A5/Letter/Legal × portrait/landscape), `CanvasMode`, `PaperTemplate`, `PaperTemplateTheme`. |
| `painters/template_painter.dart` | **New.** Vector paper ruling (lined, grid, dots, Cornell) drawn through a sink abstraction, so the screen canvas and the PDF render from one geometry definition and cannot drift apart. |
| `models/stroke.dart` | Added the `PaperTool` discriminator and derived `outlinePoints`, so line/rectangle/circle strokes render, hit-test and export from a single representation. `isEraser` is now derived from `tool`. The compact format gained an optional trailing `tool` field; data written before it still parses. |
| `widgets/paper_canvas.dart` | Page geometry comes from `pageFormat` instead of the `a4Width`/`a4Height` constants. Added the unbounded canvas mode (no page bands, no x-clamping, auto-growing 2D surface), shape-tool input handling, `getStrokesJson`/`loadStrokesJson`, `renderThumbnail`, `buildPdf` and `printPdf`. PDF export rewritten for configurable page formats, vector templates and shapes. |
| `painters/paper_painter.dart` | Renamed `a4Width`/`a4Height` → `pageWidth`/`pageHeight`; draws the paper template; suppresses page edges when the canvas is unbounded. |
| `utils/stroke_renderer_util.dart` | Added `drawShapeOutline`; shapes bypass the freehand smoothing pipeline so corners stay sharp. |
| `widgets/paper_canvas.dart` (colour) | Fixed the documented `color` property being inert: upstream seeded the pen colour from `initialColor` once in `initState` and never read `color` again, so a host toolbar could not change it. Covered by `test/host_color_test.dart`. |
| `controllers/paper_canvas_controller.dart` | Exposed the new state API. Removed `loadPdfBackground`. |
| `pubspec.yaml` | Dropped `pdfx` (used only by `loadPdfBackground`, replaced here by vector templates) and `file_picker` (declared upstream but never referenced). Corrected the SDK floor to Flutter 3.27 / Dart 3.6, which is what the code actually requires. |

The public API was renamed from the `Scribe*` prefix to `Paper*` to match this
package's name, so there is no source compatibility with upstream.

## Comparing against a newer upstream release

There is no upstream git history to merge from. To diff against a later
release, download the archive:

```sh
curl -sL https://pub.dev/api/archives/scribe_canvas-<version>.tar.gz | tar xz -C /tmp/sc-new
diff -ru /tmp/sc-new/lib lib
```
