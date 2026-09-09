# Changelog

## 1.0.0

First release.

`paper_canvas` is a derivative work of
[`scribe_canvas` v0.6.3](https://pub.dev/packages/scribe_canvas) by SKS-0212,
used under the MIT License — see [NOTICE.md](NOTICE.md) for what was inherited.
Upstream's own history is preserved in `doc/upstream_scribe_canvas_changelog.md`.

### Added

- **Configurable paper sizes.** `PageFormat` with `PaperSize` (A3, A4, A5,
  Letter, Legal) and `PageOrientation`, replacing hard-coded A4 constants.
  Dimensions are in PostScript points so screen and PDF geometry match.
  `PageFormat.fromDimensions()` recovers a format from stored dimensions, and
  `toJson`/`fromJson` let page setup travel with a document.
- **Vector paper templates.** `PaperTemplate.lined`, `.grid`, `.dots` and
  `.cornell`, drawn through a `TemplateSink` shared by the Flutter canvas and
  `PdfGraphics`, so the printed page cannot drift from the screen. Colours and
  metrics are configurable via `PaperTemplateTheme`, with `light` and `dark`
  presets. Templates can also be rendered standalone via
  `PaperTemplateRenderer` and `renderTemplateImage()`.
- **Unbounded canvas mode.** `CanvasMode.infinite` removes page bands and
  x-clamping and grows the surface in both axes as you draw. Export crops to
  the drawn region and fits it to one sheet, never scaling above 1:1.
- **Shape tools.** `PaperTool.line`, `.rectangle` and `.circle`. Shapes store
  two anchors and derive their outline on demand, so rendering, eraser
  hit-testing and PDF export all work from one representation and a shape stays
  a shape across save and reload.
- **Distinct pen and brush.** `PaperTool.pen` draws at a constant width;
  `PaperTool.brush` varies width with drawing speed.
- **Printing.** `printPdf()` opens the platform print dialog (AirPrint on iOS,
  the print framework on Android). `buildPdf()` returns raw bytes with no UI,
  for upload or preview.
- **Structured JSON persistence.** `getStrokesJson()` / `loadStrokesJson()`
  store one JSON object per stroke, alongside the existing compact string
  codec. Malformed entries are skipped rather than failing the whole load.
- **Thumbnails.** `renderThumbnail()` rasterises the content bounding box with
  its template, rather than the whole surface.
- **Introspection.** `hasStrokes`, `pageCount` and `contentBounds` on the
  controller.

### Changed

- Public API renamed from the `Scribe*` prefix to `Paper*`. There is no source
  compatibility with upstream.
- PDF export rewritten for configurable page formats, vector templates and
  shape strokes.
- Changing `pageFormat` or `canvasMode` at runtime now re-derives page count,
  cached geometry and the render cache, so page setup can be a live setting.
- Minimum SDK corrected to Flutter 3.27 / Dart 3.6, which is what the code
  actually requires (`Color.toARGB32()`, `Color.withValues()`). Upstream
  declared `flutter: ">=1.17.0"`, which would resolve on toolchains it could
  not compile against.

### Fixed

- The documented `color` property was inert: the pen colour was seeded from
  `initialColor` once in `initState` and `color` was never read again, so a host
  toolbar could not change it and every stroke came out black. Now adopted in
  `didUpdateWidget`.

### Removed

- `loadPdfBackground()`, and with it the `pdfx` dependency — vector templates
  cover the same need without a second PDF engine. Use `setBackgroundImage()`
  for image backgrounds.
- The unused `file_picker` dependency, which upstream declared but never
  referenced.
