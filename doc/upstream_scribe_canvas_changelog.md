## 0.6.3

*   **Discrete Page Navigation**:
    *   Added `ScribeScrollMode` with `continuous` (default) and `discrete` options.
    *   In **discrete mode**, vertical scrolling is disabled, and the canvas snaps to a single page at a time.
    *   Introduced a compact, vertical **Navigation Control** on the left side of the screen for flipping through pages in discrete mode.
    *   Automatic Snap: Adding or inserting a page now automatically navigates the viewport to the newly created page.
*   **Customization**:
    *   Added `eraserIcon` support to `ScribeCanvas` and `PageHeader`, allowing users to replace the default tool icon.
    *   Added `eraserIconSize`, `eraserActiveColor`, and `eraserInactiveColor` for finer control over tool styling.
*   **API Improvements**:
    *   Exported `ScribeScrollMode` enum for library consumers.
    *   Added `initialPageIndex` and `scrollMode` parameters to `ScribeCanvas`.
*   **UI/UX**:
    *   Navigation controls now automatically fade when at the start/end of the document.
    *   Refined the "Add Page" and "Insert Page" flow for a more seamless multi-page experience.

## 0.6.2

*   **Enhanced PDF Export**:
    *   **Optional Sharing**: Added a `share` boolean parameter to `exportToPdf`. Set to `false` to suppress the share sheet and just receive data.
    *   **Return PDF Bytes**: `exportToPdf` now returns `Future<Uint8List?>`, allowing you to store the generated PDF in a variable for server uploads or local processing.
    *   **Custom Filename**: Added an optional `fileName` parameter to specify the default name used in the share dialog.
*   **Cross-Platform Parity**: Ensured consistent behavior for background rendering and byte returns across Mobile, Web, and Desktop.

## 0.6.1

*   **Intelligent Clear Canvas**: Refined the `clear()` function with three specialized logic cases for page management:
    *   **Case 1 (No Background)**: Resets the canvas to a single fresh blank page.
    *   **Case 2 (Single background image/1-page PDF)**: Resets the canvas to exactly one page containing the background template, removing extra pages.
    *   **Case 3 (Multi-page background PDF)**: Preserves all template pages to maintain document integrity while clearing all drawing data.
*   **Data Integrity**: `clear()` now wipes both global and page-specific undo/redo stacks to ensure a total reset of the drawing session.
*   **`clearBackgrounds()`**: Added a dedicated method to `ScribeCanvasController` and `ScribeCanvasState` to allow removing background images or PDF templates without affecting user drawings.
*   **Viewport UX**: `clear()` automatically triggers a `resetView()` call, snapping the camera back to the top of Page 1 for immediate visual confirmation of the fresh start.

## 0.6.0

*   **O(1) Vector Caching**: Introduced a sophisticated `ui.Picture` caching system that "bakes" committed strokes into a single vector snapshot. This resolves performance lag by shifting rendering costs from O(N) to O(1) per frame.
*   **Smart Stroke Eraser**: Replaced pixel-based erasing with an intelligent object-based eraser.
    *   **Live Highlighting**: Strokes turning transparent instantly when touched by the eraser for real-time feedback.
    *   **Selection Logic**: Entire strokes are removed on contact, mimicking professional note-taking apps.
    *   **Accuracy**: High-precision Point-to-Segment intersection math for pixel-perfect hit-testing.
*   **Performance Optimizations**:
    *   Removed expensive `saveLayer()` and `BlendMode.clear` from the active-drawing path.
    *   Eliminated redundant multi-pass smoothing during live drags to ensure absolute minimum latency.
*   **Documentation**: Updated README with Performance Architecture details and version 0.6.0 features.

## 0.5.0

* **Controller Pattern**: Introduced `ScribeCanvasController` — the standard Flutter controller pattern for all imperative canvas operations. `GlobalKey<ScribeCanvasState>` is no longer needed and `ScribeCanvasState` is no longer exported from the public API.
* **Variable-Width Strokes**: High-density sampling with central difference tangents, Catmull-Rom splines, and multi-pass smoothing filters for authentic ink-like drawing.
* **Zoom Improvements**: Dynamic zoom constraints prevent infinite zoom-out. Pages snap to top-center alignment. Unified focus-based keyboard input.
* **Network Image Error Handling**: Robust error handling for `setNetworkBackgroundImage`, `setNetworkHeaderImage`, and `setNetworkFooterImage`.
* Full variable-width data preservation across all serialization formats and PDF exports.

## 0.4.0

* **Fixed Initial Visibility**: Resolved a race condition where the canvas remained invisible until manual interaction on certain devices. Initialization now correctly waits for valid layout constraints via `LayoutBuilder`.
* **Matrix4 Modernization**: Replaced deprecated `Matrix4` methods with `translateByDouble` and `scaleByDouble` to ensure long-term stability and pass modern static analysis.
* **Inversion Safety**: Fixed a critical `ArgumentError` (Matrix cannot be inverted) by ensuring correct homogeneous coordinates in transformation matrices.
* **Dependency Upgrades**: `file_picker` upgraded to `^10.3.10`, `pdfx` upgraded to `^2.9.2`.
* Code cleanup and removal of unused internal imports.

## 0.3.0

* Initial release of the Scribe library.
* Support for a multi-page A4 canvas with zooming, panning, and background templates.
* Customizable pen and eraser tools with an integrated `PageHeader` tool switcher and size cycling.
* Serialization and deserialization for saving and loading drawing strokes.
* PDF export functionality using the `pdf` and `printing` packages.
