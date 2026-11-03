import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pan/zoom the sheet only; formula input and tool targets keep their size.
/// Only rows intersecting the transformed viewport are built.
class SheetViewport extends StatefulWidget {
  const SheetViewport({
    super.key,
    required this.width,
    required this.rowCount,
    required this.rowBuilder,
    required this.header,
    this.rowExtent = 56,
  });
  final double width, rowExtent;
  final int rowCount;
  final IndexedWidgetBuilder rowBuilder;
  final Widget header;
  @override
  State<SheetViewport> createState() => SheetViewportState();
}

class SheetViewportState extends State<SheetViewport> {
  final transform = TransformationController();
  Size _size = Size.zero;
  double get zoom => transform.value.getMaxScaleOnAxis();
  void reset() => transform.value = Matrix4.identity();
  void setZoom(double value) {
    final scale = value.clamp(.5, 3.0).toDouble();
    final focal = _size.center(Offset.zero);
    final scene = transform.toScene(focal);
    final height = (widget.rowCount + 1) * widget.rowExtent;
    final x = (focal.dx - scene.dx * scale).clamp(
      math.min(0.0, _size.width - widget.width * scale),
      0.0,
    );
    final y = (focal.dy - scene.dy * scale).clamp(
      math.min(0.0, _size.height - height * scale),
      0.0,
    );
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
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
              final top = [
                viewport.point0.y,
                viewport.point1.y,
                viewport.point2.y,
                viewport.point3.y,
              ].reduce(math.min);
              final bottom = [
                viewport.point0.y,
                viewport.point1.y,
                viewport.point2.y,
                viewport.point3.y,
              ].reduce(math.max);
              final first = (top / widget.rowExtent - 2).floor().clamp(
                0,
                widget.rowCount - 1,
              );
              final last = (bottom / widget.rowExtent + 1).ceil().clamp(
                first,
                widget.rowCount - 1,
              );
              return SizedBox(
                width: widget.width,
                height: (widget.rowCount + 1) * widget.rowExtent,
                child: Stack(
                  key: const Key('grid-rows'),
                  children: [
                    for (var row = first; row <= last; row++)
                      Positioned(
                        top: (row + 1) * widget.rowExtent,
                        left: 0,
                        width: widget.width,
                        height: widget.rowExtent,
                        child: widget.rowBuilder(context, row),
                      ),
                    Positioned(
                      top: math.max(0, top),
                      left: 0,
                      width: widget.width,
                      height: widget.rowExtent,
                      child: widget.header,
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
