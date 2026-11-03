import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../native/grid_layout.dart';
import '../native/grid_window.dart';

/// Document geometry is zoomed; editor controls remain outside this viewport.
class SheetViewport extends StatefulWidget {
  const SheetViewport({
    super.key,
    required this.width,
    required this.rowCount,
    required this.rowBuilder,
    required this.header,
    this.rowExtent = 56,
  }) : columnCount = null,
       cellBuilder = null,
       columnHeaderBuilder = null,
       rowHeaderBuilder = null,
       corner = null,
       onWindowChanged = null,
       columnExtent = 116,
       rowHeaderExtent = 52,
       layout = null,
       onResize = null;
  const SheetViewport.cells({
    super.key,
    required this.rowCount,
    required int columnCount,
    required this.cellBuilder,
    required this.columnHeaderBuilder,
    required this.rowHeaderBuilder,
    required this.corner,
    this.onWindowChanged,
    this.layout,
    this.onResize,
    this.rowExtent = 56,
    this.columnExtent = 116,
    this.rowHeaderExtent = 52,
  }) : columnCount = columnCount,
       width = rowHeaderExtent + columnCount * columnExtent,
       rowBuilder = null,
       header = null;
  final double width, rowExtent, columnExtent, rowHeaderExtent;
  final int rowCount;
  final int? columnCount;
  final IndexedWidgetBuilder? rowBuilder, columnHeaderBuilder, rowHeaderBuilder;
  final Widget Function(BuildContext, int row, int column)? cellBuilder;
  final Widget? header, corner;
  final GridLayout? layout;
  final ValueChanged<GridWindow>? onWindowChanged;
  final Future<void> Function(bool row, int index, double size)? onResize;
  @override
  State<SheetViewport> createState() => SheetViewportState();
}

class SheetViewportState extends State<SheetViewport> {
  final transform = TransformationController();
  Size _size = Size.zero;
  GridWindow? _lastRegion;
  GridAxis? _previewRows, _previewColumns;
  bool? _resizingRow;
  int _resizeIndex = 0;
  double _resizeStart = 0, _resizeExtent = 0, _resizeSize = 0;
  bool _committingSize = false;
  GridAxis get rows =>
      _previewRows ??
      widget.layout?.rows ??
      GridAxis(widget.rowCount, widget.rowExtent);
  GridAxis get columns =>
      _previewColumns ??
      widget.layout?.columns ??
      GridAxis(widget.columnCount ?? 1, widget.columnExtent);
  double get zoom => transform.value.getMaxScaleOnAxis();
  double get _heading => widget.rowExtent;
  double get _width =>
      widget.cellBuilder == null ? widget.width : columns.total;
  double get _height => widget.cellBuilder == null
      ? (widget.rowCount + 1) * widget.rowExtent
      : rows.total;
  void reset() {
    _lastRegion = null;
    transform.value = Matrix4.identity();
  }

  void goToCell(int row, int column) => _translate(
    widget.cellBuilder == null
        ? column * widget.columnExtent
        : columns.offset(column),
    widget.cellBuilder == null ? row * widget.rowExtent : rows.offset(row),
    zoom,
  );
  void _translate(double left, double top, double scale) {
    final x = (-left * scale).clamp(
      math.min(0.0, _size.width - _width * scale),
      0.0,
    );
    final y = (-top * scale).clamp(
      math.min(0.0, _size.height - _height * scale),
      0.0,
    );
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw(x.toDouble(), y.toDouble(), 0);
  }

  void setZoom(double value) {
    final scene = transform.toScene(Offset.zero);
    _translate(scene.dx, scene.dy, value.clamp(.5, 5.0).toDouble());
  }

  void _beginResize(bool row, int index, LongPressStartDetails details) {
    if (widget.onResize == null || _committingSize) return;
    Feedback.forLongPress(context);
    setState(() {
      _resizingRow = row;
      _resizeIndex = index;
      _resizeStart = row
          ? details.globalPosition.dy
          : details.globalPosition.dx;
      _resizeExtent = _resizeSize = (row ? rows : columns).extent(index);
    });
  }

  void _moveResize(LongPressMoveUpdateDetails details) {
    final row = _resizingRow;
    if (row == null || _committingSize) return;
    final delta =
        (row ? details.globalPosition.dy : details.globalPosition.dx) -
        _resizeStart;
    setState(() {
      _resizeSize = (_resizeExtent + delta / zoom)
          .clamp(4.0, 4096.0)
          .roundToDouble();
      if (row) {
        _previewRows =
            (widget.layout?.rows ?? GridAxis(widget.rowCount, widget.rowExtent))
                .resized(_resizeIndex, _resizeSize);
      } else {
        _previewColumns =
            (widget.layout?.columns ??
                    GridAxis(widget.columnCount!, widget.columnExtent))
                .resized(_resizeIndex, _resizeSize);
      }
    });
  }

  void _clearResize() {
    if (!mounted) return;
    setState(() {
      _resizingRow = null;
      _previewRows = null;
      _previewColumns = null;
      _committingSize = false;
    });
  }

  Future<void> _endResize(LongPressEndDetails _) async {
    if (_resizingRow == null || _committingSize) return;
    _committingSize = true;
    try {
      if ((_resizeSize - _resizeExtent).abs() >= .5) {
        await widget.onResize!(_resizingRow!, _resizeIndex, _resizeSize);
      }
    } finally {
      _clearResize();
    }
  }

  Widget _resizeHeader(bool row, int index, Widget child) => GestureDetector(
    key: ValueKey('grid-${row ? 'row' : 'column'}-header-$index'),
    behavior: HitTestBehavior.opaque,
    onLongPressStart: widget.onResize == null
        ? null
        : (d) => _beginResize(row, index, d),
    onLongPressMoveUpdate: widget.onResize == null ? null : _moveResize,
    onLongPressEnd: widget.onResize == null ? null : _endResize,
    onLongPressCancel: _committingSize ? null : _clearResize,
    child: Semantics(
      hint: tr(context, 'Удерживайте и тяните для изменения размера'),
      child: child,
    ),
  );
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Widget _viewer() => ColoredBox(
    color: Colors.white,
    child: InteractiveViewer.builder(
      key: const Key('sheet-viewport'),
      transformationController: transform,
      minScale: .5,
      maxScale: 5,
      panEnabled: _resizingRow == null,
      scaleEnabled: _resizingRow == null,
      builder: (context, viewport) {
        final points = [
          viewport.point0,
          viewport.point1,
          viewport.point2,
          viewport.point3,
        ];
        final top = math.max(0.0, points.map((p) => p.y).reduce(math.min));
        final left = math.max(0.0, points.map((p) => p.x).reduce(math.min));
        final bottom = points.map((p) => p.y).reduce(math.max);
        final right = points.map((p) => p.x).reduce(math.max);
        if (widget.cellBuilder == null) {
          final first = (top / widget.rowExtent - 2).floor().clamp(
            0,
            widget.rowCount - 1,
          );
          final last = (bottom / widget.rowExtent + 1).ceil().clamp(
            first,
            widget.rowCount - 1,
          );
          return SizedBox(
            width: _width,
            height: _height,
            child: Stack(
              key: const Key('grid-rows'),
              children: [
                for (var row = first; row <= last; row++)
                  Positioned(
                    top: (row + 1) * widget.rowExtent,
                    left: 0,
                    width: _width,
                    height: widget.rowExtent,
                    child: widget.rowBuilder!(context, row),
                  ),
                Positioned(
                  top: top,
                  left: 0,
                  width: _width,
                  height: widget.rowExtent,
                  child: widget.header!,
                ),
              ],
            ),
          );
        }
        final rowAxis = rows, colAxis = columns;
        final rowList = rowAxis.visible(top, bottom),
            colList = colAxis.visible(left, right);
        if (rowList.isNotEmpty && colList.isNotEmpty && _resizingRow == null) {
          final region = GridWindow.visible(0, rowList, colList);
          if (_lastRegion == null ||
              !listEquals(_lastRegion!.rowIndices, rowList) ||
              !listEquals(_lastRegion!.columnIndices, colList)) {
            _lastRegion = region;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onWindowChanged?.call(region);
            });
          }
        }
        // Filter once per frame instead of scanning every imported merge per cell.
        final candidates = rowList.isEmpty || colList.isEmpty
            ? <GridMerge>[]
            : (widget.layout?.merges ?? <GridMerge>[])
                  .where(
                    (m) =>
                        m.row <= rowList.last &&
                        m.endRow >= rowList.first &&
                        m.column <= colList.last &&
                        m.endColumn >= colList.first,
                  )
                  .toList();
        final merges = <GridMerge>{}, children = <Widget>[];
        for (final row in rowList) {
          for (final col in colList) {
            GridMerge? merge;
            for (final candidate in candidates) {
              if (candidate.contains(row, col)) {
                merge = candidate;
                break;
              }
            }
            if (merge != null) {
              merges.add(merge);
              continue;
            }
            children.add(
              Positioned(
                key: ValueKey('cell-position-$row-$col'),
                top: rowAxis.offset(row),
                left: colAxis.offset(col),
                width: colAxis.extent(col),
                height: rowAxis.extent(row),
                child: widget.cellBuilder!(context, row, col),
              ),
            );
          }
        }
        for (final merge in merges) {
          children.add(
            Positioned(
              key: ValueKey('merge-position-${merge.address}'),
              top: rowAxis.offset(merge.row),
              left: colAxis.offset(merge.column),
              width:
                  colAxis.offset(merge.endColumn + 1) -
                  colAxis.offset(merge.column),
              height:
                  rowAxis.offset(merge.endRow + 1) - rowAxis.offset(merge.row),
              child: widget.cellBuilder!(context, merge.row, merge.column),
            ),
          );
        }
        return SizedBox(
          width: _width,
          height: _height,
          child: Stack(key: const Key('grid-rows'), children: children),
        );
      },
    ),
  );

  /// Headings live outside the document transform: text and touch width stay
  /// constant while cell geometry follows the same matrix as the canvas.
  Widget _headings() => ValueListenableBuilder<Matrix4>(
    valueListenable: transform,
    builder: (context, matrix, _) {
      final scale = zoom, rowAxis = rows, colAxis = columns;
      final top = transform.toScene(Offset.zero),
          bottom = transform.toScene(Offset(_size.width, _size.height));
      final rowList = rowAxis.visible(top.dy, bottom.dy),
          colList = colAxis.visible(top.dx, bottom.dx);
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: _heading,
            bottom: 0,
            width: widget.rowHeaderExtent,
            child: widget.corner!,
          ),
          for (final row in rowList)
            Positioned(
              key: ValueKey('row-position-$row'),
              top: _heading + rowAxis.offset(row) * scale + matrix.storage[13],
              left: 0,
              width: widget.rowHeaderExtent,
              height: rowAxis.extent(row) * scale,
              child: _resizeHeader(
                true,
                row,
                widget.rowHeaderBuilder!(context, row),
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: _heading,
            child: widget.corner!,
          ),
          for (final col in colList)
            Positioned(
              key: ValueKey('column-position-$col'),
              top: 0,
              left:
                  widget.rowHeaderExtent +
                  colAxis.offset(col) * scale +
                  matrix.storage[12],
              width: colAxis.extent(col) * scale,
              height: _heading,
              child: _resizeHeader(
                false,
                col,
                widget.columnHeaderBuilder!(context, col),
              ),
            ),
          Positioned(
            key: const ValueKey('grid-corner'),
            top: 0,
            left: 0,
            width: widget.rowHeaderExtent,
            height: _heading,
            child: widget.corner!,
          ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cellMode = widget.cellBuilder != null;
      _size = cellMode
          ? Size(
              math.max(0, box.maxWidth - widget.rowHeaderExtent),
              math.max(0, box.maxHeight - _heading),
            )
          : box.biggest;
      return ClipRect(
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cellMode) ...[
                Positioned.fill(
                  left: widget.rowHeaderExtent,
                  top: _heading,
                  child: _viewer(),
                ),
                _headings(),
              ] else
                _viewer(),
              if (_resizingRow != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: IgnorePointer(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '${tr(context, _resizingRow! ? 'Высота строки' : 'Ширина столбца')}: ${_resizeSize.round()} px',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
