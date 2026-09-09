# paper_canvas

A multi-page handwriting and drawing canvas for Flutter, with configurable
paper sizes, vector paper templates, an unbounded canvas mode, shape tools, and
**true vector** PDF export and printing.

> **Credit.** `paper_canvas` is a derivative work of
> [**`scribe_canvas`** by SKS-0212](https://pub.dev/packages/scribe_canvas),
> used and modified under the MIT License. The drawing engine at its core —
> picture-cached rendering, the variable-width ink renderer, the object eraser,
> and the vector PDF approach — is their work. See [NOTICE.md](NOTICE.md) for a
> full breakdown of what was inherited and what was added here.

---

## Why this exists

Most Flutter drawing packages hand you an infinite white sheet and a PNG at the
end of it. This one is built for **notes and documents**: real paper sizes, real
ruling, and a PDF you can actually print.

- **Vector, not pixels.** Strokes are re-emitted as PDF paths through
  `PdfGraphics`, so a page is roughly 12 KB and stays sharp at any zoom or print
  size. Not a screenshot wrapped in a PDF.
- **The screen and the page agree.** Paper templates are defined once and
  replayed into both the Flutter `Canvas` and the PDF, so what prints is what
  you drew.
- **O(1) rendering.** Completed strokes are baked into a `ui.Picture`; only the
  active stroke is processed per frame, so a page with thousands of strokes
  still draws at 60fps.

## Contents

- [Install](#install) · [Quick start](#quick-start)
- [Paper sizes](#paper-sizes) · [Templates](#paper-templates) · [Canvas modes](#canvas-modes)
- [Tools](#tools) · [Pages](#page-management) · [Navigation](#navigation)
- [Backgrounds, headers & footers](#backgrounds-headers-and-footers)
- [PDF export & printing](#pdf-export-and-printing) · [Persistence](#persistence) · [Thumbnails](#thumbnails)
- [Full API reference](#api-reference) · [Recipes](#recipes)

---

## Install

```yaml
dependencies:
  paper_canvas: ^0.2.0
```

Requires **Flutter 3.27 / Dart 3.6** or newer. Supports Android, iOS, macOS,
Windows and Linux.

## Quick start

```dart
import 'package:paper_canvas/paper_canvas.dart';

final controller = PaperCanvasController();

PaperCanvas(
  controller: controller,
  tool: PaperTool.brush,
  color: Colors.black,
  strokeWidth: 4,
  pageFormat: const PageFormat(size: PaperSize.a4),
  canvasMode: CanvasMode.paged,
  template: PaperTemplate.cornell,
  templateTheme: PaperTemplateTheme.light,
);
```

A complete runnable app — toolbar, page setup sheet, export and print — is in
[`example/`](example).

---

## Paper sizes

```dart
const PageFormat(size: PaperSize.a3, orientation: PageOrientation.landscape)
```

| `PaperSize` | Portrait (pt) |
| --- | --- |
| `a3` | 841.89 × 1190.55 |
| `a4` | 595.28 × 841.89 |
| `a5` | 419.53 × 595.28 |
| `letter` | 612 × 792 |
| `legal` | 612 × 1008 |

`PageOrientation.portrait` or `.landscape`. Width and height are already
swapped for landscape, so you never handle orientation yourself.

Dimensions are in **PostScript points** — the same unit the `pdf` package uses
— so on-screen geometry and exported geometry are the same numbers, with no
conversion step to get wrong.

```dart
format.width          // 841.89
format.height         // 1190.55
format.pageSize       // Size
format.pdfPageFormat  // PdfPageFormat, for the pdf package
format.isLandscape
format.label          // "A3 Landscape"
format.copyWith(size: PaperSize.a4)

// Recover a format from stored dimensions (null if they match no sheet)
PageFormat.fromDimensions(595.28, 841.89);

// Round-trip through JSON
format.toJson();
PageFormat.fromJson(map);
```

## Paper templates

All ruling is drawn as **vectors**, so it stays crisp at any zoom and prints
identically to what is on screen.

| `PaperTemplate` | Description |
| --- | --- |
| `blank` | No ruling. |
| `lined` | Ruled baselines with a left margin rule. |
| `grid` | Squared paper, 5 mm by default. |
| `dots` | Dot grid, 5 mm by default. |
| `cornell` | Cornell notes: title strip, cue column, notes area, summary band. |

Tune them with `PaperTemplateTheme`:

```dart
const PaperTemplateTheme(
  lineColor:   Color(0xFFB9C6D6), // baselines, grid lines, dots
  accentColor: Color(0xFFE8A0A0), // margin rules, Cornell dividers
  pageColor:   Color(0xFFFFFFFF), // the paper itself
  lineSpacing: 24.0,              // points; ~8mm ruling
  gridSpacing: 14.17,             // points; 5mm
  lineWidth:   0.6,
)
```

`PaperTemplateTheme.light` and `PaperTemplateTheme.dark` are provided; use
`copyWith` to adjust one value.

Templates can also be rendered directly, outside a canvas:

```dart
// into any Flutter Canvas
PaperTemplateRenderer.paintToCanvas(
  canvas: canvas, origin: Offset.zero,
  template: PaperTemplate.lined, pageSize: format.pageSize,
  theme: PaperTemplateTheme.light,
);

// as a pw.Widget for the pdf package
PaperTemplateRenderer.pdfWidget(
  template: PaperTemplate.grid, pageSize: format.pageSize,
  theme: PaperTemplateTheme.light,
);

// or rasterised
final ui.Image image = await renderTemplateImage(
  template: PaperTemplate.dots, pageSize: format.pageSize,
  theme: PaperTemplateTheme.light, pixelRatio: 2,
);
```

Implement `TemplateSink` to render the ruling somewhere else entirely.

## Canvas modes

```dart
CanvasMode.paged     // a stack of fixed-size pages
CanvasMode.infinite  // one unbounded 2D surface
```

- **`paged`** — pages laid out top to bottom. A stroke's page is derived from
  its y coordinate; strokes are clamped to the page width. Export produces one
  PDF page per canvas page, growing to fit any ink past the last known page.
- **`infinite`** — no page bands, no clamping, and the surface grows outward as
  you approach its edge. Export crops to the drawn region and fits it onto a
  single sheet, **never scaling above 1:1**, so a small sketch prints at its
  true size instead of being blown up.

Switching mode or paper size at runtime re-derives page count and geometry, so
you can offer it as a live setting.

The unbounded surface starts at `infiniteCanvasMinSize` (default
`Size(10000, 15000)`) and grows to keep `infiniteCanvasMargin` (default `2000`)
of slack beyond the drawn content:

```dart
PaperCanvas(
  canvasMode: CanvasMode.infinite,
  infiniteCanvasMinSize: const Size(20000, 20000),
  infiniteCanvasMargin: 4000,
)
```

## Tools

```dart
PaperCanvas(tool: PaperTool.brush, ...)
```

| `PaperTool` | Behaviour |
| --- | --- |
| `pen` | Freehand at a constant width. |
| `brush` | Freehand whose width tracks drawing speed, giving an ink-like taper. |
| `line` | Straight line between two anchors. |
| `rectangle` | Axis-aligned rectangle. |
| `circle` | Ellipse inscribed in the drag bounds. |
| `eraser` | **Object eraser** — removes whole strokes it touches, rather than painting over them. |

Shapes store exactly two anchor points and derive their outline on demand, so a
rectangle stays a rectangle through save and reload rather than degrading into
a polyline that happens to look rectangular.

`PaperTool.isShape` and `.isVariableWidth` are available for building toolbars.

Colour and width are host-driven via `color`, `strokeWidth` and `eraserWidth`,
and changes apply to subsequent strokes.

## Page management

```dart
controller.addPage();       // append
controller.insertPage(1);   // insert, shifting later strokes down
controller.deletePage(1);   // delete, shifting later strokes up
controller.pageCount;
```

Undo/redo works both globally and per page:

```dart
controller.undo();
controller.redo();
controller.undoPage(0);
controller.redoPage(0);
controller.canUndo;
controller.canRedo;
controller.clear();
```

## Navigation

- Pinch to zoom, drag to pan; `isPanMode: true` disables drawing so a single
  finger pans instead.
- `ScrollMode.continuous` (default) scrolls freely; `ScrollMode.discrete`
  snaps page by page.
- `initialPageIndex` sets the starting page.
- `controller.resetView()` returns to the default zoom and position.
- Palm rejection is applied to touch input while a stylus is in use.

## Backgrounds, headers and footers

Per-page background images, and header/footer images repeated on every exported
page:

```dart
await controller.setBackgroundImage(0, bytes, clearOthers: true);
await controller.setNetworkBackgroundImage(0, 'https://…/bg.png');
controller.clearBackgrounds();

await controller.setHeaderImage(bytes);
await controller.setNetworkHeaderImage('https://…/logo.png');
await controller.setFooterImage(bytes);
await controller.setNetworkFooterImage('https://…/footer.png');
```

Setting a background for page 0 only makes it repeat on every page.

## PDF export and printing

```dart
// Share sheet
await controller.exportToPdf(fileName: 'notes.pdf');

// Platform print dialog (AirPrint on iOS, print framework on Android)
await controller.printPdf(documentName: 'Notes');

// Raw bytes, no UI — for upload, caching or preview
final Uint8List? bytes = await controller.buildPdf();
```

Output is **vector**: variable-width ink is emitted as filled polygon
envelopes, shapes as constant-width outlines, and templates as stroked paths.
Page size follows `pageFormat`, and templates, backgrounds, headers and footers
are all composited in.

Returns `null` when nothing has been drawn.

## Persistence

Structured JSON — one object per stroke, ideal when the destination stores
real JSON:

```dart
final List<Map<String, dynamic>> strokes = controller.getStrokesJson();
controller.loadStrokesJson(strokes);
```

Or the compact string codec (delta-encoded, much smaller):

```dart
final String data = controller.getEncodedData();
controller.loadEncodedData(data);
```

Malformed entries are skipped rather than aborting the load, so one bad stroke
cannot cost the user the rest of the drawing.

`Stroke` is exported, so you can inspect or transform strokes yourself —
`points`, `widths`, `color`, `strokeWidth`, `tool`, `bounds`, `outlinePoints`,
`isPointNear()`, `simplify()` (Ramer–Douglas–Peucker), plus `toJson`/`fromJson`
and `serialize`/`deserialize`.

## Thumbnails

```dart
final ui.Image? image = await controller.renderThumbnail(
  maxDimension: 512,
  padding: 24,
);
```

Renders the **content bounding box** with its paper template, not the whole
surface — on an infinite canvas the drawing is usually a small corner of a very
large document, so rasterising all of it would be slow and mostly blank.

```dart
controller.hasStrokes;     // is anything drawn
controller.contentBounds;  // Rect? of the committed ink
```

---

## API reference

### `PaperCanvas`

| Property | Type | Default | Purpose |
| --- | --- | --- | --- |
| `controller` | `PaperCanvasController?` | — | Imperative control. |
| `tool` | `PaperTool?` | `null` | Active tool; falls back to `isEraser`. |
| `color` | `Color` | `black` | Pen colour for subsequent strokes. |
| `strokeWidth` | `double` | `4.0` | Pen width. |
| `eraserWidth` | `double` | `30.0` | Eraser hit radius. |
| `pageFormat` | `PageFormat` | A4 portrait | Paper size and orientation. |
| `canvasMode` | `CanvasMode` | `paged` | Paged or unbounded. |
| `infiniteCanvasMinSize` | `Size` | `10000x15000` | Minimum unbounded surface. |
| `infiniteCanvasMargin` | `double` | `2000` | Slack kept beyond the content. |
| `template` | `PaperTemplate` | `blank` | Paper ruling. |
| `templateTheme` | `PaperTemplateTheme` | `light` | Ruling colours and metrics. |
| `multiPage` | `bool` | `true` | Allow more than one page. |
| `isPanMode` | `bool` | `false` | Disable drawing, pan only. |
| `isEraser` | `bool` | `false` | Legacy eraser toggle; prefer `tool`. |
| `scrollMode` | `ScrollMode` | `continuous` | Free or page-snapped scrolling. |
| `initialPageIndex` | `int` | `0` | Starting page. |
| `strokeSizes` | `List<double>` | `[2,4,8,16,32]` | Sizes the built-in header cycles. |
| `eraserSizes` | `List<double>` | `[10,20,30,60,100]` | Eraser sizes it cycles. |
| `colors` | `List<Color>` | 6 colours | Built-in palette. |
| `initialColor` | `Color` | `black` | Palette starting colour. |
| `eraserIcon`, `eraserIconSize`, `eraserActiveColor`, `eraserInactiveColor` | — | — | Built-in header styling. |

**Callbacks:** `onStrokeStart`, `onStrokeEnd`, `onUndo`, `onRedo`,
`onColorChanged`, `onStrokeWidthChanged`, `onEraserWidthChanged`,
`onToggleEraser`.

### `PaperCanvasController`

| Member | Purpose |
| --- | --- |
| `clear()` | Remove all strokes and history. |
| `undo()` / `redo()` | Global undo/redo. |
| `undoPage(i)` / `redoPage(i)` | Per-page undo/redo. |
| `canUndo` / `canRedo` | Availability. |
| `addPage()` / `insertPage(i)` / `deletePage(i)` | Page management. |
| `pageCount` | Number of pages (always 1 when infinite). |
| `hasStrokes` | Whether anything is drawn. |
| `contentBounds` | `Rect?` of committed ink. |
| `resetView()` | Reset zoom and pan. |
| `exportToPdf()` / `printPdf()` / `buildPdf()` | Export and print. |
| `getStrokesJson()` / `loadStrokesJson()` | Structured JSON. |
| `getEncodedData()` / `loadEncodedData()` | Compact string codec. |
| `renderThumbnail()` | Rasterise the drawn area. |
| `setBackgroundImage()` / `setNetworkBackgroundImage()` / `clearBackgrounds()` | Page backgrounds. |
| `setHeaderImage()` / `setFooterImage()` (+ network variants) | Export headers/footers. |

Dispose it with `controller.dispose()`.

---

## Recipes

### Host-driven toolbar

`PaperCanvas` renders its own per-page header with colour, stroke-width and
eraser controls. If your app has its own toolbar, mirror the callbacks back so
the two never disagree:

```dart
PaperCanvas(
  controller: controller,
  tool: _tool,
  color: _color,
  strokeWidth: _width,
  onColorChanged:       (c) => setState(() => _color = c),
  onStrokeWidthChanged: (w) => setState(() => _width = w),
  onEraserWidthChanged: (w) => setState(() => _eraserWidth = w),
  onToggleEraser:       (e) => setState(() =>
      _tool = e ? PaperTool.eraser : _lastDrawTool),
  onStrokeEnd: () => setState(() {}), // refresh undo/redo enablement
)
```

### Saving a document with its page settings

`PageFormat` serialises to JSON, so page setup can travel with the strokes:

```dart
final doc = {
  'format':  format.toJson(),
  'mode':    mode.name,
  'template': template.name,
  'strokes': controller.getStrokesJson(),
};
```

### Uploading a PDF instead of sharing it

```dart
final bytes = await controller.buildPdf();
if (bytes != null) await api.upload(bytes);
```

---

## Tests

```sh
flutter test
```

Covers vector PDF export (page formats, page counts, templates, shapes,
infinite-canvas fitting), runtime page-geometry changes, and host-driven
colour.

## License

MIT — see [LICENSE](LICENSE). Derived from `scribe_canvas` by SKS-0212, whose
copyright is retained; see [NOTICE.md](NOTICE.md).
