import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../widgets/scribe_canvas.dart';

/// A controller for a [ScribeCanvas] widget.
///
/// This controller allows you to imperatively control a ScribeCanvas widget,
/// such as managing pages, rendering backgrounds, saving/loading data,
/// and executing undo/redo actions without needing a GlobalKey.
class ScribeCanvasController extends ChangeNotifier {
  ScribeCanvasState? _state;

  /// Whether the controller is currently attached to a ScribeCanvas widget.
  bool get isAttached => _state != null;

  /// Attaches the controller to a ScribeCanvas state.
  /// This is called automatically by [ScribeCanvas] — do not call manually.
  @internal
  void attach(ScribeCanvasState state) {
    _state = state;
  }

  /// Detaches the controller from the currently attached state.
  /// This is called automatically by [ScribeCanvas] — do not call manually.
  @internal
  void detach() {
    _state = null;
  }

  /// Clears all strokes from the canvas.
  void clear() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.clear();
    notifyListeners();
  }

  /// Clears all background images and PDF templates from the canvas.
  void clearBackgrounds() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.clearBackgrounds();
    notifyListeners();
  }

  /// Undoes the last stroke globally.
  void undo() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.undo();
  }

  /// Redoes the last undone stroke globally.
  void redo() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.redo();
  }

  /// Undoes the last stroke on a specific page.
  void undoPage(int pageIndex) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.undoPage(pageIndex);
  }

  /// Redoes the last undone stroke on a specific page.
  void redoPage(int pageIndex) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.redoPage(pageIndex);
  }

  /// Adds a new page to the end of the document.
  void addPage() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.addPage();
  }

  /// Deletes a page at the given index.
  void deletePage(int index) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.deletePage(index);
  }

  /// Inserts a page at the given index.
  void insertPage(int index) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.insertPage(index);
  }

  /// Sets an image background for a specific page using local bytes.
  Future<void> setBackgroundImage(int pageIndex, Uint8List bytes, {bool clearOthers = false}) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    await _state?.setBackgroundImage(pageIndex, bytes, clearOthers: clearOthers);
  }

  /// Sets an image background for a specific page from a network URL.
  Future<void> setNetworkBackgroundImage(int pageIndex, String url, {bool clearOthers = false}) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    await _state?.setNetworkBackgroundImage(pageIndex, url, clearOthers: clearOthers);
  }


  /// Sets a header image from local bytes that repeats on all exported pages.
  Future<void> setHeaderImage(Uint8List bytes) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    await _state?.setHeaderImage(bytes);
  }

  /// Sets a header image from a network URL that repeats on all exported pages.
  Future<void> setNetworkHeaderImage(String url) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    await _state?.setNetworkHeaderImage(url);
  }

  /// Sets a footer image from local bytes that repeats on all exported pages.
  Future<void> setFooterImage(Uint8List bytes) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    await _state?.setFooterImage(bytes);
  }

  /// Sets a footer image from a network URL that repeats on all exported pages.
  Future<void> setNetworkFooterImage(String url) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    await _state?.setNetworkFooterImage(url);
  }

  /// Exports the canvas to a PDF.
  /// If [share] is true, it shares the PDF using the system share sheet.
  /// Returns the PDF bytes if successful.
  Future<Uint8List?> exportToPdf({String? fileName, bool share = true}) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return await _state?.exportToPdf(fileName: fileName, share: share);
  }

  /// Opens the platform print dialog for the current drawing.
  ///
  /// Returns true if the job was submitted, false if there was nothing to
  /// print or the user cancelled.
  Future<bool> printPdf({String? documentName}) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return await _state?.printPdf(documentName: documentName) ?? false;
  }

  /// Builds the PDF without sharing or printing it -- for uploading, caching
  /// or previewing.
  Future<Uint8List?> buildPdf() async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return await _state?.buildPdf();
  }

  /// Whether anything has been drawn.
  bool get hasStrokes => _state?.hasStrokes ?? false;

  /// Number of canvas pages (always 1 for an infinite canvas).
  int get pageCount => _state?.pageCount ?? 1;

  /// Bounding box of the committed ink, or null when nothing is drawn.
  Rect? get contentBounds => _state?.contentBounds;

  /// The strokes as structured JSON, one object per stroke.
  List<Map<String, dynamic>> getStrokesJson() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return _state?.getStrokesJson() ?? const <Map<String, dynamic>>[];
  }

  /// Replaces the canvas contents from [getStrokesJson] output.
  void loadStrokesJson(List<dynamic> json) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.loadStrokesJson(json);
    notifyListeners();
  }

  /// Rasterises the drawing and its paper template for use as a thumbnail.
  Future<ui.Image?> renderThumbnail({
    double maxDimension = 512,
    double padding = 24,
  }) async {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return await _state?.renderThumbnail(
      maxDimension: maxDimension,
      padding: padding,
    );
  }

  /// Gets the encoded stroke data as a JSON string.
  String getEncodedData() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return _state!.getEncodedData();
  }

  /// Loads encoded JSON stroke data into the canvas.
  void loadEncodedData(String encodedData) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.loadEncodedData(encodedData);
  }

  /// Gets legacy encoded stroke data (base64).
  String getLegacyEncodedData() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return _state!.getLegacyEncodedData();
  }

  /// Loads legacy encoded stroke data (base64) into the canvas.
  void loadLegacyEncodedData(String encodedData) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.loadLegacyEncodedData(encodedData);
  }

  /// Unified loader that automatically detects if the data is in Modern or Legacy format.
  void loadData(String data) {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.loadData(data);
  }

  /// Returns the current strokes as a single encoded string (Modern format).
  String saveData() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    return getEncodedData();
  }

  /// Resets the canvas viewport to its initial position and scale.
  void resetView() {
    assert(isAttached, "ScribeCanvasController is not attached to a ScribeCanvas");
    _state?.resetView();
  }

  /// Checks if undo is possible.
  bool get canUndo {
    if (!isAttached) return false;
    return _state!.canUndo;
  }

  /// Checks if redo is possible.
  bool get canRedo {
    if (!isAttached) return false;
    return _state!.canRedo;
  }
}
