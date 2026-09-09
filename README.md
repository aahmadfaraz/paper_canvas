# scribe_canvas (SchoolHack fork)

A multi-page handwriting and drawing canvas for Flutter, with configurable
paper sizes, vector paper templates, an unbounded canvas mode, shape tools, and
**true vector** PDF export and printing.

Forked from [`scribe_canvas` v0.6.3](https://pub.dev/packages/scribe_canvas)
(MIT, © SKS-0212) and maintained in-house. See [VENDORING.md](VENDORING.md) for
why it is forked and exactly what was changed.

## Install

```yaml
dependencies:
  scribe_canvas:
    # path: ../packages/scribe_canvas   # uncomment for local development
    git:
      url: https://github.com/aahmadfaraz/scribe_canvas
      ref: <commit-sha>
```

Pin `ref` to a commit rather than a branch, so a push to `main` cannot change
what an existing checkout resolves to.

## Features

- **Paper sizes** — A3 / A4 / A5 / Letter / Legal, portrait or landscape.
- **Paper templates** — blank, lined, squares, dot grid, Cornell notes, drawn as
  vectors so they stay crisp at any zoom and print identically to the screen.
- **Two canvas modes** — a stack of fixed pages, or one unbounded 2D surface
  that grows as you draw.
- **Tools** — pen (constant width), brush (velocity-driven variable width),
  line, rectangle, circle, and an object eraser that removes whole strokes.
- **Vector PDF export and printing** — strokes are re-emitted as PDF paths via
  `PdfGraphics`, not rasterised, so output is small and sharp at any size.
  Printing goes through the platform dialog (AirPrint / Android print).
- **Structured JSON** — `getStrokesJson()` / `loadStrokesJson()` for storing
  strokes as ordinary JSON objects, plus a compact string codec.

## Usage

```dart
final controller = ScribeCanvasController();

ScribeCanvas(
  controller: controller,
  tool: ScribeTool.brush,
  color: Colors.black,
  strokeWidth: 4,
  pageFormat: const ScribePageFormat(size: ScribePaperSize.a4),
  canvasMode: ScribeCanvasMode.paged,
  template: ScribePaperTemplate.cornell,
  templateTheme: ScribeTemplateTheme.light,
);
```

```dart
// Export and print
await controller.exportToPdf(fileName: 'notes.pdf'); // share sheet
await controller.printPdf(documentName: 'Notes');    // platform print dialog
final bytes = await controller.buildPdf();           // raw bytes, no UI

// Persist
final strokes = controller.getStrokesJson();
controller.loadStrokesJson(strokes);

// Thumbnail of the drawn area, with its template
final image = await controller.renderThumbnail();
```

### Host-driven vs built-in controls

`ScribeCanvas` renders its own per-page header with colour, stroke-width and
eraser controls. If the host app supplies its own toolbar, mirror the widget's
callbacks (`onColorChanged`, `onStrokeWidthChanged`, `onEraserWidthChanged`,
`onToggleEraser`) back into host state so the two stay in sync.

## Tests

```sh
flutter test
```

Covers vector PDF export (page formats, page counts, templates, shapes,
infinite-canvas fitting), runtime page-geometry changes, and host-driven
colour.

## License

MIT — see [LICENSE](LICENSE). Upstream copyright is retained.
