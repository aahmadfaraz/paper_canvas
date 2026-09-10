# Changelog

## 0.2.2

Packaging only -- no functional change.

### Fixed

- The `LICENSE` file is once again recognised as MIT. An explanatory paragraph
  about the derivation had been inserted into the license body, which stopped
  pub.dev's license detector matching it against the canonical MIT text. The
  file is now verbatim MIT, retaining both copyright holders; the derivation is
  documented in `NOTICE.md` and the README, where it belongs.
- Shortened the pubspec description to 158 characters. It was 207, over the
  180-character limit pub.dev checks, which meant search engines truncated it.

## 0.2.1

### Added

- `PaperCanvas.canvasColor` sets the paper colour directly, without having to
  construct a whole `PaperTemplateTheme` just to change the sheet. It composes
  with the theme rather than replacing it, so the ruling colours and metrics
  are preserved, and it applies everywhere paper is drawn -- the canvas, the
  exported PDF and thumbnails. Defaults to null, meaning the theme's own
  `pageColor` (white for `PaperTemplateTheme.light`), so existing behaviour and
  the `PaperTemplateTheme.dark` preset are unchanged.

The default pen colour was already a parameter: `PaperCanvas.color`, which
defaults to black. Its seeding from `initialColor` no longer compares against
an inline colour literal.

## 0.2.0

### Fixed

- The `CanvasMode.infinite` surface was far too small. Its size was derived
  from the page format (two pages plus a margin), giving roughly 3191x3684
  points on A4 -- only a few screens in each direction, which does not feel
  unbounded. It now defaults to a 10000x15000 minimum and still grows beyond
  that to keep a margin past the drawn content.

### Added

- `PaperCanvas.infiniteCanvasMinSize` (default `Size(10000, 15000)`) and
  `PaperCanvas.infiniteCanvasMargin` (default `2000`) make the unbounded
  surface configurable instead of implied by the page size.

### Changed

- The render cache no longer opens a document-sized `saveLayer` unless an
  eraser stroke is actually present. Erasers remove whole strokes and are never
  persisted, so the layer was only ever needed for imported legacy data -- and
  its cost scales with the canvas, which now matters.

## 0.1.0

First release.

Published as 0.x while the API settles: under semver, breaking changes
before 1.0.0 land as a minor bump (0.2.0) rather than a major one.

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
