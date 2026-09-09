import 'package:flutter/material.dart';
import 'package:paper_canvas/paper_canvas.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'paper_canvas',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const CanvasDemo(),
    );
  }
}

class CanvasDemo extends StatefulWidget {
  const CanvasDemo({super.key});

  @override
  State<CanvasDemo> createState() => _CanvasDemoState();
}

class _CanvasDemoState extends State<CanvasDemo> {
  final PaperCanvasController _controller = PaperCanvasController();

  PaperTool _tool = PaperTool.brush;

  /// Restored when the eraser is switched off, so toggling it does not
  /// silently drop you back to the pen.
  PaperTool _lastDrawTool = PaperTool.brush;

  Color _color = Colors.black;
  double _strokeWidth = 4;
  double _eraserWidth = 30;
  bool _panMode = false;

  PageFormat _format = const PageFormat();
  CanvasMode _mode = CanvasMode.paged;
  PaperTemplate _template = PaperTemplate.lined;

  static const List<Color> _palette = <Color>[
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.green,
    Colors.blue,
    Colors.purple,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isInfinite => _mode == CanvasMode.infinite;

  void _selectTool(PaperTool tool) {
    setState(() {
      _tool = tool;
      if (tool != PaperTool.eraser) _lastDrawTool = tool;
      _panMode = false;
    });
  }

  Future<void> _export() async {
    final bytes = await _controller.exportToPdf(fileName: 'drawing.pdf');
    if (bytes == null && mounted) _toast('Draw something first.');
  }

  Future<void> _print() async {
    if (!_controller.hasStrokes) {
      _toast('Draw something first.');
      return;
    }
    await _controller.printPdf(documentName: 'Drawing');
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('paper_canvas'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Page setup',
            icon: const Icon(Icons.tune),
            onPressed: _openPageSetup,
          ),
          IconButton(
            tooltip: 'Share as PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _export,
          ),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: _print,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PaperCanvas(
              controller: _controller,
              tool: _tool,
              color: _color,
              strokeWidth: _strokeWidth,
              eraserWidth: _eraserWidth,
              isPanMode: _panMode,
              pageFormat: _format,
              canvasMode: _mode,
              template: _template,
              templateTheme:
                  dark ? PaperTemplateTheme.dark : PaperTemplateTheme.light,
              multiPage: !_isInfinite,
              initialColor: _color,
              // The canvas has its own per-page header. Mirroring its callbacks
              // back into this state keeps it and the bottom bar in agreement.
              onColorChanged: (c) => setState(() => _color = c),
              onStrokeWidthChanged: (w) => setState(() => _strokeWidth = w),
              onEraserWidthChanged: (w) => setState(() => _eraserWidth = w),
              onToggleEraser: (isEraser) => setState(() {
                if (isEraser) {
                  if (_tool != PaperTool.eraser) _lastDrawTool = _tool;
                  _tool = PaperTool.eraser;
                } else {
                  _tool = _lastDrawTool;
                }
              }),
              // Undo/redo availability is not listenable, so refresh on change.
              onStrokeEnd: () => setState(() {}),
              onUndo: () => setState(() {}),
              onRedo: () => setState(() {}),
            ),
          ),
          _Toolbar(
            tool: _tool,
            panMode: _panMode,
            color: _color,
            palette: _palette,
            isInfinite: _isInfinite,
            hasStrokes: _controller.hasStrokes,
            onTool: _selectTool,
            onColor: (c) => setState(() => _color = c),
            onTogglePan: () => setState(() => _panMode = !_panMode),
            onUndo: _controller.undo,
            onRedo: _controller.redo,
            onAddPage: _controller.addPage,
            onClear: () => setState(_controller.clear),
          ),
        ],
      ),
    );
  }

  void _openPageSetup() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Canvas',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _Chips<CanvasMode>(
                    values: CanvasMode.values,
                    selected: _mode,
                    label: (m) => m.label,
                    onSelect: (m) => update(() => _mode = m),
                  ),
                  const SizedBox(height: 16),
                  Text(_isInfinite ? 'Export page size' : 'Page size',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  _Chips<PaperSize>(
                    values: PaperSize.values,
                    selected: _format.size,
                    label: (s) => s.label,
                    onSelect: (s) =>
                        update(() => _format = _format.copyWith(size: s)),
                  ),
                  const SizedBox(height: 16),
                  const Text('Orientation',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _Chips<PageOrientation>(
                    values: PageOrientation.values,
                    selected: _format.orientation,
                    label: (o) => o.label,
                    onSelect: (o) => update(
                        () => _format = _format.copyWith(orientation: o)),
                  ),
                  const SizedBox(height: 16),
                  const Text('Paper',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _Chips<PaperTemplate>(
                    values: PaperTemplate.values,
                    selected: _template,
                    label: (t) => t.label,
                    onSelect: (t) => update(() => _template = t),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: values
          .map((v) => ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                onSelected: (_) => onSelect(v),
              ))
          .toList(),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tool,
    required this.panMode,
    required this.color,
    required this.palette,
    required this.isInfinite,
    required this.hasStrokes,
    required this.onTool,
    required this.onColor,
    required this.onTogglePan,
    required this.onUndo,
    required this.onRedo,
    required this.onAddPage,
    required this.onClear,
  });

  final PaperTool tool;
  final bool panMode;
  final Color color;
  final List<Color> palette;
  final bool isInfinite;
  final bool hasStrokes;
  final ValueChanged<PaperTool> onTool;
  final ValueChanged<Color> onColor;
  final VoidCallback onTogglePan;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onAddPage;
  final VoidCallback onClear;

  static const Map<PaperTool, IconData> _icons = <PaperTool, IconData>{
    PaperTool.pen: Icons.edit_outlined,
    PaperTool.brush: Icons.brush_outlined,
    PaperTool.line: Icons.horizontal_rule,
    PaperTool.rectangle: Icons.rectangle_outlined,
    PaperTool.circle: Icons.circle_outlined,
    PaperTool.eraser: Icons.backspace_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              for (final entry in _icons.entries)
                IconButton(
                  tooltip: entry.key.name,
                  icon: Icon(entry.value),
                  color: entry.key == tool && !panMode ? scheme.primary : null,
                  onPressed: () => onTool(entry.key),
                ),
              const VerticalDivider(width: 12),
              for (final c in palette)
                GestureDetector(
                  onTap: () => onColor(c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == color ? scheme.primary : Colors.black26,
                        width: c == color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              const VerticalDivider(width: 12),
              IconButton(
                tooltip: panMode ? 'Draw' : 'Pan & zoom',
                icon: Icon(panMode ? Icons.pan_tool : Icons.pan_tool_outlined),
                color: panMode ? scheme.primary : null,
                onPressed: onTogglePan,
              ),
              IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo),
                  onPressed: onUndo),
              IconButton(
                  tooltip: 'Redo',
                  icon: const Icon(Icons.redo),
                  onPressed: onRedo),
              if (!isInfinite)
                IconButton(
                  tooltip: 'Add page',
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: onAddPage,
                ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline),
                color: Colors.redAccent,
                onPressed: hasStrokes ? onClear : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
