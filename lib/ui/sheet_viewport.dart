import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' as gestures;
import 'package:flutter/physics.dart' as physics;

import '../l10n/app_strings.dart';
import '../native/grid_layout.dart';
import '../native/grid_window.dart';
import '../native/grid_selection.dart';

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
       columnHeaderExtent = rowExtent,
       layout = null,
       onResize = null,
       compactCellsBuilder = null,
       onCellTap = null,
       onCellLongPress = null,
       freezeHeadings = false,
       selection = null,
       onSelectionChanged = null,
       onSelectionEnd = null;
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
    this.compactCellsBuilder,
    this.onCellTap,
    this.onCellLongPress,
    this.freezeHeadings = false,
    this.selection,
    this.onSelectionChanged,
    this.onSelectionEnd,
    this.rowExtent = 56,
    this.columnExtent = 116,
    this.rowHeaderExtent = 52,
    this.columnHeaderExtent = 56,
  }) : columnCount = columnCount,
       width = rowHeaderExtent + columnCount * columnExtent,
       rowBuilder = null,
       header = null;
  final double width,
      rowExtent,
      columnExtent,
      rowHeaderExtent,
      columnHeaderExtent;
  final int rowCount;
  final int? columnCount;
  final IndexedWidgetBuilder? rowBuilder, columnHeaderBuilder, rowHeaderBuilder;
  final Widget Function(BuildContext, int row, int column)? cellBuilder;
  final Widget? header, corner;
  final GridLayout? layout;
  final Widget Function(BuildContext, Rect, GridAxis, GridAxis)?
  compactCellsBuilder;
  final void Function(int row, int column)? onCellTap, onCellLongPress;
  final bool freezeHeadings;
  final GridSelection? selection;
  final ValueChanged<GridSelection>? onSelectionChanged;
  final VoidCallback? onSelectionEnd;
  final ValueChanged<GridWindow>? onWindowChanged;
  final Future<void> Function(bool row, int index, double size)? onResize;
  @override
  State<SheetViewport> createState() => SheetViewportState();
}

class SheetViewportState extends State<SheetViewport>
    with SingleTickerProviderStateMixin {
  final transform = TransformationController();
  late final AnimationController _inertia;
  Offset _inertiaStart = Offset.zero, _inertiaVelocity = Offset.zero;
  bool _multiTouch = false;
  @override
  void initState() {
    super.initState();
    _inertia = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        final before = Offset(
          transform.value.storage[12],
          transform.value.storage[13],
        );
        _matrix(
          zoom,
          _inertiaStart.dx + _inertiaVelocity.dx * _inertia.value,
          _inertiaStart.dy + _inertiaVelocity.dy * _inertia.value,
        );
        final after = Offset(
          transform.value.storage[12],
          transform.value.storage[13],
        );
        if (_inertia.value > 0 && (after - before).distance < .001) {
          _inertia.stop();
        }
      });
  }

  void _scaleEnd(ScaleEndDetails details) {
    if (_multiTouch ||
        _resizingRow != null ||
        _draggingCorner != null ||
        details.pointerCount != 0) {
      return;
    }
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.distance < 80) return;
    _inertiaStart = Offset(
      transform.value.storage[12],
      transform.value.storage[13],
    );
    _inertiaVelocity = velocity;
    _inertia.value = 0;
    _inertia.animateWith(physics.FrictionSimulation(.0000135, 0, 1));
  }

  Size _size = Size.zero;
  Offset _gestureScene = Offset.zero;
  final _pointers = <int, Offset>{};
  Offset? _pendingScene;
  double _pendingScale = 1;
  void _captureGestureOrigin() {
    if (_pointers.isEmpty) {
      _pendingScene = null;
      return;
    }
    final focal =
        _pointers.values.reduce((a, b) => a + b) / _pointers.length.toDouble();
    _pendingScene = documentPoint(focal);
    _pendingScale = zoom;
  }

  double _gestureScale = 1;
  double get minimumZoom => widget.cellBuilder == null ? .5 : .1;
  Offset paddingAt(double scale) => widget.cellBuilder == null
      ? Offset.zero
      : Offset(widget.rowHeaderExtent, _heading);
  Offset get _padding => paddingAt(zoom);
  Offset documentPoint(Offset screen) => Offset(
    (screen.dx - _padding.dx - transform.value.storage[12]) / zoom,
    (screen.dy - _padding.dy - transform.value.storage[13]) / zoom,
  );
  Offset screenPoint(Offset document) =>
      document * zoom +
      _padding +
      Offset(transform.value.storage[12], transform.value.storage[13]);
  void _matrix(double scale, double x, double y) {
    final padding = paddingAt(scale);
    double constrain(double value, double viewport, double end) =>
        value.clamp(math.min(0.0, viewport - end * scale), 0.0).toDouble();

    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw(
        constrain(x, _size.width - padding.dx, _width),
        constrain(y, _size.height - padding.dy, _height),
        0,
      );
  }

  void _scaleStart(ScaleStartDetails details) {
    _inertia.stop();
    _gestureScene = _pendingScene ?? documentPoint(details.localFocalPoint);
    _gestureScale = _pendingScene == null ? zoom : _pendingScale;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    if (_resizingRow != null || _draggingCorner != null) return;
    final scale = (_gestureScale * details.scale)
        .clamp(minimumZoom, 5.0)
        .toDouble();
    final padding = paddingAt(scale);
    _matrix(
      scale,
      details.localFocalPoint.dx - padding.dx - _gestureScene.dx * scale,
      details.localFocalPoint.dy - padding.dy - _gestureScene.dy * scale,
    );
  }

  void _report(GridWindow region) {
    final previous = _lastRegion;
    if (previous != null &&
        previous.covers(region) &&
        region.covers(previous)) {
      return;
    }
    _lastRegion = region;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onWindowChanged?.call(region);
    });
  }

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
  double get _heading => widget.columnHeaderExtent;
  double get _width =>
      widget.cellBuilder == null ? widget.width : columns.total;
  double get _height => widget.cellBuilder == null
      ? (widget.rowCount + 1) * widget.rowExtent
      : rows.total;
  void reset() {
    _rangeScroll?.cancel();
    _draggingCorner = null;
    _inertia.stop();
    _lastRegion = null;
    transform.value = Matrix4.identity();
  }

  void goToCell(int row, int column) {
    _inertia.stop();
    final scale = zoom;
    _translate(
      widget.cellBuilder == null
          ? column * widget.columnExtent
          : columns.offset(column),
      widget.cellBuilder == null ? row * widget.rowExtent : rows.offset(row),
      scale,
    );
  }

  void _translate(double left, double top, double scale) {
    _matrix(scale, -left * scale, -top * scale);
  }

  void setZoom(double value) {
    _inertia.stop();
    final scene = widget.cellBuilder == null
        ? transform.toScene(Offset.zero)
        : documentPoint(_padding);
    _translate(
      scene.dx.clamp(0, _width).toDouble(),
      scene.dy.clamp(0, _height).toDouble(),
      value.clamp(minimumZoom, 5.0).toDouble(),
    );
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
      child: ClipRect(child: child),
    ),
  );
  @override
  void dispose() {
    _inertia.dispose();
    _rangeScroll?.cancel();
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
        final bottom = points.map((p) => p.y).reduce(math.max);
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
        return const SizedBox.shrink();
      },
    ),
  );

  Widget _cells(Rect rect) {
    final top = math.max(0.0, rect.top), left = math.max(0.0, rect.left);
    final bottom = rect.bottom, right = rect.right;
    final rowAxis = rows, colAxis = columns;
    final rowList = rowAxis.visible(top, bottom),
        colList = colAxis.visible(left, right);
    if (rowList.isNotEmpty && colList.isNotEmpty && _resizingRow == null) {
      _report(
        GridWindow.visible(
          0,
          rowAxis.visible(top, bottom, buffer: 6),
          colAxis.visible(left, right, buffer: 4),
        ),
      );
    }

    if (zoom < .5 && widget.compactCellsBuilder != null) {
      final visible = Rect.fromLTRB(
        left,
        top,
        math.min(right, _width),
        math.min(bottom, _height),
      );
      return SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          children: [
            Positioned(
              left: visible.left,
              top: visible.top,
              width: visible.width,
              height: visible.height,
              child: widget.compactCellsBuilder!(
                context,
                visible,
                rowAxis,
                colAxis,
              ),
            ),
          ],
        ),
      );
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
          height: rowAxis.offset(merge.endRow + 1) - rowAxis.offset(merge.row),
          child: widget.cellBuilder!(context, merge.row, merge.column),
        ),
      );
    }
    return SizedBox(
      width: _width,
      height: _height,
      child: Stack(key: const Key('grid-rows'), children: children),
    );
  }

  Offset _selectionPointer = Offset.zero, _selectionScene = Offset.zero;
  int _selectionAnchorRow = 0, _selectionAnchorColumn = 0;
  bool? _draggingCorner;
  Timer? _rangeScroll;
  Offset _rangePointer = Offset.zero, _rangeTranslation = Offset.zero;
  void _startRangeScroll() {
    _rangeScroll?.cancel();
    _rangeScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _draggingCorner == null) {
        _rangeScroll?.cancel();
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox) return;
      final point = box.globalToLocal(_rangePointer);
      double speed(double value, double length) => value < 36
          ? ((36 - value) / 36).clamp(0.0, 1.0) * 8
          : value > length - 36
          ? -((value - length + 36) / 36).clamp(0.0, 1.0) * 8
          : 0;
      final before = Offset(
        transform.value.storage[12],
        transform.value.storage[13],
      );
      final next = Offset(
        (before.dx + speed(point.dx, _size.width))
            .clamp(
              math.min(0.0, _size.width - _padding.dx - _width * zoom),
              0.0,
            )
            .toDouble(),
        (before.dy + speed(point.dy, _size.height))
            .clamp(
              math.min(0.0, _size.height - _padding.dy - _height * zoom),
              0.0,
            )
            .toDouble(),
      );
      if (next == before) return;
      _matrix(zoom, next.dx, next.dy);
      if (!_publishSelection()) {
        _matrix(zoom, before.dx, before.dy);
        _rangeScroll?.cancel();
      }
    });
  }

  void _beginSelection(bool start, DragStartDetails details) {
    final value = widget.selection!;
    _inertia.stop();
    _draggingCorner = start;
    _selectionPointer = _rangePointer = details.globalPosition;
    _rangeTranslation = Offset(
      transform.value.storage[12],
      transform.value.storage[13],
    );
    _startRangeScroll();
    final row = start ? value.row : value.endRow,
        col = start ? value.column : value.endColumn;
    _selectionScene = Offset(
      columns.offset(col) + columns.extent(col) / 2,
      rows.offset(row) + rows.extent(row) / 2,
    );
    _selectionAnchorRow = start ? value.endRow : value.row;
    _selectionAnchorColumn = start ? value.endColumn : value.column;
  }

  void _moveSelection(DragUpdateDetails details) {
    _rangePointer = details.globalPosition;
    if (_rangeScroll?.isActive != true) _startRangeScroll();
    _publishSelection();
  }

  bool _publishSelection() {
    final start = _draggingCorner;
    if (start == null) return false;
    final translation = Offset(
      transform.value.storage[12],
      transform.value.storage[13],
    );
    final point =
        _selectionScene +
        (_rangePointer -
                _selectionPointer -
                (translation - _rangeTranslation)) /
            zoom;
    final row = rows.indexAt(point.dy.clamp(0, rows.total).toDouble());
    final col = columns.indexAt(point.dx.clamp(0, columns.total).toDouble());
    final value = start
        ? GridSelection(
            math.min(row, _selectionAnchorRow),
            math.min(col, _selectionAnchorColumn),
            _selectionAnchorRow,
            _selectionAnchorColumn,
          )
        : GridSelection(
            _selectionAnchorRow,
            _selectionAnchorColumn,
            math.max(row, _selectionAnchorRow),
            math.max(col, _selectionAnchorColumn),
          );
    if (value.cellCount > GridSelection.maxCells) return false;
    widget.onSelectionChanged?.call(value);
    return true;
  }

  void _endSelection() {
    _rangeScroll?.cancel();
    _draggingCorner = null;
    widget.onSelectionEnd?.call();
  }

  List<Widget> _selectionWidgets() {
    final value = widget.selection;
    if (value == null) return const [];
    final rect = Rect.fromPoints(
      screenPoint(Offset(columns.offset(value.column), rows.offset(value.row))),
      screenPoint(
        Offset(
          columns.offset(value.endColumn + 1),
          rows.offset(value.endRow + 1),
        ),
      ),
    );
    Widget handle(bool start) {
      final point = start ? rect.topLeft : rect.bottomRight;
      if (_size.shortestSide < 44 ||
          (!(Offset.zero & _size).contains(point) &&
              _draggingCorner != start)) {
        return const SizedBox.shrink();
      }
      final center =
          (point + (start ? const Offset(-22, -22) : const Offset(22, 22)));
      final x = center.dx.clamp(22.0, _size.width - 22),
          y = center.dy.clamp(22.0, _size.height - 22);
      return Positioned(
        left: x - 22,
        top: y - 22,
        width: 44,
        height: 44,
        child: GestureDetector(
          key: ValueKey(start ? 'grid-selection-start' : 'grid-selection-end'),
          dragStartBehavior: gestures.DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _beginSelection(start, d),
          onPanUpdate: _moveSelection,
          onPanEnd: (_) => _endSelection(),
          onPanCancel: _endSelection,
          child: Semantics(
            label: tr(context, start ? 'Начало диапазона' : 'Конец диапазона'),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xff188458),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _RangePainter(rect))),
      ),
      if (widget.onSelectionChanged != null) ...[handle(true), handle(false)],
    ];
  }

  Widget _cellSurface() => Listener(
    onPointerDown: (e) {
      _inertia.stop();
      if (_pointers.isEmpty) _multiTouch = false;
      _pointers[e.pointer] = e.localPosition;
      if (_pointers.length > 1) _multiTouch = true;
      _captureGestureOrigin();
    },
    onPointerMove: (e) => _pointers[e.pointer] = e.localPosition,
    onPointerUp: (e) {
      _pointers.remove(e.pointer);
      _captureGestureOrigin();
    },
    onPointerCancel: (e) {
      _pointers.remove(e.pointer);
      _captureGestureOrigin();
    },
    child: GestureDetector(
      key: const Key('sheet-viewport'),
      dragStartBehavior: gestures.DragStartBehavior.down,
      behavior: HitTestBehavior.opaque,
      onScaleStart: _scaleStart,
      onScaleUpdate: _scaleUpdate,
      onScaleEnd: _scaleEnd,
      onTapUp: (details) {
        if (zoom >= .5 || widget.compactCellsBuilder == null) return;
        final point = documentPoint(details.localPosition);
        if (point.dx < 0 ||
            point.dy < 0 ||
            point.dx >= _width ||
            point.dy >= _height) {
          return;
        }
        widget.onCellTap?.call(
          rows.indexAt(point.dy),
          columns.indexAt(point.dx),
        );
      },
      onLongPressStart: (details) {
        if (zoom >= .5 || widget.compactCellsBuilder == null) return;
        final point = documentPoint(details.localPosition);
        if (point.dx < 0 ||
            point.dy < 0 ||
            point.dx >= _width ||
            point.dy >= _height) {
          return;
        }
        widget.onCellLongPress?.call(
          rows.indexAt(point.dy),
          columns.indexAt(point.dx),
        );
      },
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: transform,
        builder: (context, matrix, _) {
          final top = documentPoint(Offset.zero),
              bottom = documentPoint(Offset(_size.width, _size.height));
          final canvas = Matrix4.copy(matrix)
            ..setTranslationRaw(
              matrix.storage[12] + _padding.dx,
              matrix.storage[13] + _padding.dy,
              0,
            );
          final cells = _cells(Rect.fromPoints(top, bottom));
          final selection = _selectionWidgets();
          return Stack(
            fit: StackFit.expand,
            children: [
              OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: _width,
                maxWidth: _width,
                minHeight: _height,
                maxHeight: _height,
                child: Transform(
                  alignment: Alignment.topLeft,
                  transform: canvas,
                  child: cells,
                ),
              ),
              if (selection.isNotEmpty) selection.first,
              _headings(),
              ...selection.skip(1),
            ],
          );
        },
      ),
    ),
  );

  /// Headings live outside the document transform: text and touch width stay
  /// constant while cell geometry follows the same matrix as the canvas.
  Widget _headings() => ValueListenableBuilder<Matrix4>(
    valueListenable: transform,
    builder: (context, matrix, _) {
      final scale = zoom, rowAxis = rows, colAxis = columns;
      final top = documentPoint(Offset.zero),
          bottom = documentPoint(Offset(_size.width, _size.height));
      final rowList = rowAxis.visible(top.dy, bottom.dy),
          colList = colAxis.visible(top.dx, bottom.dx);
      final edgeX = widget.freezeHeadings ? 0.0 : matrix.storage[12];
      final edgeY = widget.freezeHeadings ? 0.0 : matrix.storage[13];
      return Stack(
        children: [
          Positioned(
            left: edgeX,
            top: edgeY + _heading,
            bottom: 0,
            width: widget.rowHeaderExtent,
            child: widget.corner!,
          ),
          for (final row in rowList)
            Positioned(
              key: ValueKey('row-position-$row'),
              top: _heading + rowAxis.offset(row) * scale + matrix.storage[13],
              left: edgeX,
              width: widget.rowHeaderExtent,
              height: rowAxis.extent(row) * scale,
              child: _resizeHeader(
                true,
                row,
                widget.rowHeaderBuilder!(context, row),
              ),
            ),
          Positioned(
            left: edgeX,
            top: edgeY,
            right: 0,
            height: _heading,
            child: widget.corner!,
          ),
          for (final col in colList)
            Positioned(
              key: ValueKey('column-position-$col'),
              top: edgeY,
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
            top: edgeY,
            left: edgeX,
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
      _size = box.biggest;
      return ClipRect(
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cellMode) _cellSurface() else _viewer(),
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

class _RangePainter extends CustomPainter {
  _RangePainter(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = const Color(0x12188458));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xff188458)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RangePainter old) => rect != old.rect;
}
