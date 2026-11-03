import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../native/grid_window.dart';

/// Only intersecting rows/columns are mounted; controls stay outside zoom.
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
       rowHeaderExtent = 52;
  const SheetViewport.cells({
    super.key,
    required this.rowCount,
    required int columnCount,
    required this.cellBuilder,
    required this.columnHeaderBuilder,
    required this.rowHeaderBuilder,
    required this.corner,
    this.onWindowChanged,
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
  final ValueChanged<GridWindow>? onWindowChanged;
  @override
  State<SheetViewport> createState() => SheetViewportState();
}

class SheetViewportState extends State<SheetViewport> {
  final transform = TransformationController();
  Size _size = Size.zero;
  GridWindow? _lastRegion;
  double get zoom => transform.value.getMaxScaleOnAxis();
  double get _height => (widget.rowCount + 1) * widget.rowExtent;
  void reset() {
    _lastRegion = null;
    transform.value = Matrix4.identity();
  }

  void goToCell(int row, int column) {
    final scale = zoom;
    final x = (-column * widget.columnExtent * scale).clamp(
      math.min(0.0, _size.width - widget.width * scale),
      0.0,
    );
    final y = (-row * widget.rowExtent * scale).clamp(
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
    final scale = value.clamp(.5, 3.0).toDouble();
    final scene = transform.toScene(Offset.zero);
    final x = (-scene.dx * scale).clamp(
      math.min(0.0, _size.width - widget.width * scale),
      0.0,
    );
    final y = (-scene.dy * scale).clamp(
      math.min(0.0, _size.height - _height * scale),
      0.0,
    );
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw(x.toDouble(), y.toDouble(), 0);
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _size = box.biggest;
      return ColoredBox(
        color: Colors.white,
        child: InteractiveViewer.builder(
          key: const Key('sheet-viewport'),
          transformationController: transform,
          minScale: .5,
          maxScale: 3,
          builder: (context, viewport) {
            final top = math.max(
              0.0,
              [
                viewport.point0.y,
                viewport.point1.y,
                viewport.point2.y,
                viewport.point3.y,
              ].reduce(math.min),
            );
            final bottom = [
              viewport.point0.y,
              viewport.point1.y,
              viewport.point2.y,
              viewport.point3.y,
            ].reduce(math.max);
            final left = math.max(
              0.0,
              [
                viewport.point0.x,
                viewport.point1.x,
                viewport.point2.x,
                viewport.point3.x,
              ].reduce(math.min),
            );
            final right = [
              viewport.point0.x,
              viewport.point1.x,
              viewport.point2.x,
              viewport.point3.x,
            ].reduce(math.max);
            final first = (top / widget.rowExtent - 2).floor().clamp(
              0,
              widget.rowCount - 1,
            );
            final last = (bottom / widget.rowExtent + 1).ceil().clamp(
              first,
              widget.rowCount - 1,
            );
            if (widget.cellBuilder == null) {
              return SizedBox(
                width: widget.width,
                height: _height,
                child: Stack(
                  key: const Key('grid-rows'),
                  children: [
                    for (var row = first; row <= last; row++)
                      Positioned(
                        top: (row + 1) * widget.rowExtent,
                        left: 0,
                        width: widget.width,
                        height: widget.rowExtent,
                        child: widget.rowBuilder!(context, row),
                      ),
                    Positioned(
                      top: top,
                      left: 0,
                      width: widget.width,
                      height: widget.rowExtent,
                      child: widget.header!,
                    ),
                  ],
                ),
              );
            }
            final startCol =
                ((left - widget.rowHeaderExtent) / widget.columnExtent - 1)
                    .floor()
                    .clamp(0, widget.columnCount! - 1);
            final endCol =
                ((right - widget.rowHeaderExtent) / widget.columnExtent + 1)
                    .ceil()
                    .clamp(startCol, widget.columnCount! - 1);
            final region = GridWindow(
              0,
              first,
              startCol,
              rows: last - first + 1,
              columns: endCol - startCol + 1,
            );
            final previous = _lastRegion;
            if (previous == null ||
                previous.row != region.row ||
                previous.column != region.column ||
                previous.rows != region.rows ||
                previous.columns != region.columns) {
              _lastRegion = region;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.onWindowChanged?.call(region);
              });
            }
            return SizedBox(
              width: widget.width,
              height: _height,
              child: Stack(
                key: const Key('grid-rows'),
                children: [
                  for (var row = first; row <= last; row++)
                    for (var col = startCol; col <= endCol; col++)
                      Positioned(
                        top: (row + 1) * widget.rowExtent,
                        left:
                            widget.rowHeaderExtent + col * widget.columnExtent,
                        width: widget.columnExtent,
                        height: widget.rowExtent,
                        child: widget.cellBuilder!(context, row, col),
                      ),
                  for (var row = first; row <= last; row++)
                    Positioned(
                      top: (row + 1) * widget.rowExtent,
                      left: left,
                      width: widget.rowHeaderExtent,
                      height: widget.rowExtent,
                      child: widget.rowHeaderBuilder!(context, row),
                    ),
                  for (var col = startCol; col <= endCol; col++)
                    Positioned(
                      top: top,
                      left: widget.rowHeaderExtent + col * widget.columnExtent,
                      width: widget.columnExtent,
                      height: widget.rowExtent,
                      child: widget.columnHeaderBuilder!(context, col),
                    ),
                  Positioned(
                    top: top,
                    left: left,
                    width: widget.rowHeaderExtent,
                    height: widget.rowExtent,
                    child: widget.corner!,
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
