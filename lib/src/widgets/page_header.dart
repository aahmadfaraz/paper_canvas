import 'package:flutter/material.dart';

class PageHeader extends StatelessWidget {
  final int pageIndex;
  final bool isMultiPage;
  final bool isLastPage;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onInsert;
  final VoidCallback onDelete;
  final VoidCallback? onAddPage;
  final Function(double)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final double strokeWidth;
  final List<double> strokeSizes;
  final ValueChanged<double> onStrokeWidthChanged;
  final bool isEraser;
  final double eraserWidth;
  final List<double> eraserSizes;
  final ValueChanged<double> onEraserWidthChanged;
  final ValueChanged<bool> onToggleEraser;
  final Color color;
  final List<Color> colors;
  final ValueChanged<Color>? onColorChanged;
  final IconData eraserIcon;
  final double eraserIconSize;
  final Color eraserActiveColor;
  final Color eraserInactiveColor;

  const PageHeader({
    super.key,
    required this.pageIndex,
    required this.isMultiPage,
    required this.isLastPage,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onInsert,
    required this.onDelete,
    this.onAddPage,
    this.onDragUpdate,
    this.onDragEnd,
    required this.strokeWidth,
    required this.strokeSizes,
    required this.onStrokeWidthChanged,
    required this.isEraser,
    required this.eraserWidth,
    required this.eraserSizes,
    required this.onEraserWidthChanged,
    required this.onToggleEraser,
    this.color = Colors.black,
    this.colors = const [Colors.black, Colors.red, Colors.blue, Colors.green],
    this.onColorChanged,
    this.eraserIcon = Icons.clear,
    this.eraserIconSize = 18.0,
    this.eraserActiveColor = Colors.blueAccent,
    this.eraserInactiveColor = Colors.black54,
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 600;

    return Center(
      child: GestureDetector(
        onVerticalDragUpdate: onDragUpdate != null
            ? (details) => onDragUpdate!(details.delta.dy)
            : null,
        onVerticalDragEnd: onDragEnd != null ? (_) => onDragEnd!() : null,
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black12, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator, size: 16, color: Colors.black26),
              SizedBox(width: isCompact ? 4 : 8),
              Text(
                isCompact ? '${pageIndex + 1}' : 'Page ${pageIndex + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              SizedBox(width: isCompact ? 4 : 8),
              Container(width: 1, height: 16, color: Colors.black12),
              const SizedBox(width: 4),
              _buildToolButton(context, isPen: true),
              if (!isEraser && colors.isNotEmpty) ...[
                const SizedBox(width: 4),
                _buildColorButton(context),
              ],
              const SizedBox(width: 4),
              _buildToolButton(context, isPen: false),
              const SizedBox(width: 4),
              Container(width: 1, height: 16, color: Colors.black12),
              IconButton(
                icon: const Icon(Icons.undo, size: 18),
                onPressed: canUndo ? onUndo : null,
                color: Colors.black54,
                disabledColor: Colors.black12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Undo',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.redo, size: 18),
                onPressed: canRedo ? onRedo : null,
                color: Colors.black54,
                disabledColor: Colors.black12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Redo',
              ),
              if (isMultiPage) ...[
                const SizedBox(width: 8),
                Container(width: 1, height: 16, color: Colors.black12),
                const SizedBox(width: 4),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onInsert,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  color: Colors.blueAccent,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Insert Page Above',
                ),
              ],

              if (isLastPage) ...[
                const SizedBox(width: 4),
                Container(width: 1, height: 16, color: Colors.black12),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: onAddPage,
                  color: Colors.blueAccent,
                  disabledColor: Colors.black12,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Add Page Below',
                ),
              ],
              const SizedBox(width: 4),
              Container(width: 1, height: 16, color: Colors.black12),
              const SizedBox(width: 4),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete, size: 16),
                color: Colors.redAccent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Delete Page',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton(BuildContext context) {
    return Tooltip(
      message: 'Pen Color',
      child: InkWell(
        onTap: () {
          if (colors.isEmpty) return;
          int currentIndex = colors.indexOf(color);
          if (currentIndex == -1) currentIndex = 0;
          final int nextIndex = (currentIndex + 1) % colors.length;
          onColorChanged?.call(colors[nextIndex]);
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton(BuildContext context, {required bool isPen}) {
    final bool isActive = isPen ? !isEraser : isEraser;
    final IconData icon = isPen ? Icons.edit : eraserIcon;
    final Color toolColor = isPen
        ? (isActive ? color : Colors.black54)
        : (isActive ? eraserActiveColor : eraserInactiveColor);
    
    final String label = isPen
        ? strokeWidth.toStringAsFixed(0)
        : eraserWidth.toStringAsFixed(0);
    final String tooltip = isPen ? 'Pen Size: $label' : 'Eraser Size: $label';
    final List<double> sizes = isPen ? strokeSizes : eraserSizes;
    final double currentWidth = isPen ? strokeWidth : eraserWidth;
    final ValueChanged<double> onWidthChanged = isPen
        ? onStrokeWidthChanged
        : onEraserWidthChanged;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          if (!isActive) {
            onToggleEraser(!isPen);
          } else {
            if (sizes.isEmpty) return;
            int currentIndex = sizes.indexOf(currentWidth);
            if (currentIndex == -1) {
              currentIndex = 0;
            }
            final int nextIndex = (currentIndex + 1) % sizes.length;
            onWidthChanged(sizes[nextIndex]);
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? toolColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: isPen ? 18 : eraserIconSize,
                color: toolColor,
              ),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: toolColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
