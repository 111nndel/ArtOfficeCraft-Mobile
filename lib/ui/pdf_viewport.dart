import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'page_reading.dart';

/// The viewport fills the available canvas. The page starts fitted to width,
/// even when it is taller than the screen, and remains pannable at every scale.
class PdfViewport extends StatefulWidget {
  const PdfViewport({
    super.key,
    required this.image,
    required this.pageWidth,
    required this.pageHeight,
    this.turnAxis,
    this.onTurn,
    this.onPageTap,
    this.pageIdentity,
    this.highlight,
  });
  final Future<Uint8List>? image;
  final double pageWidth, pageHeight;
  final Axis? turnAxis;
  final ValueChanged<int>? onTurn;
  final ValueChanged<Offset>? onPageTap;
  final Object? pageIdentity;
  final Rect? highlight;
  @override
  State<PdfViewport> createState() => PdfViewportState();
}

class PdfViewportState extends State<PdfViewport> {
  final transform = TransformationController();
  Size _size = Size.zero;
  double get _widthScale => (_size.width - 16) / widget.pageWidth;
  double get _pageScale =>
      math.min(_widthScale, (_size.height - 16) / widget.pageHeight);
  void _fit(double scale, {double fraction = 0}) {
    if (!scale.isFinite || scale <= 0) return;
    final height = widget.pageHeight * scale;
    final scroll = (fraction * height - _size.height / 4).clamp(
      0.0,
      math.max(0.0, height - _size.height + 16),
    );
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw(
        (_size.width - widget.pageWidth * scale) / 2,
        8 - scroll.toDouble(),
        0,
      );
  }

  void fitWidth() => _fit(_widthScale);
  void fitPage() => _fit(_pageScale);

  void _reveal() => _fit(_widthScale, fraction: widget.highlight?.top ?? 0);

  bool _atEdge(int delta) => canTurnAtEdge(
    transform,
    Rect.fromLTWH(0, 0, widget.pageWidth, widget.pageHeight),
    _size,
    widget.turnAxis,
    delta,
  );
  @override
  void didUpdateWidget(covariant PdfViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.pageIdentity ?? widget.image) !=
            (oldWidget.pageIdentity ?? oldWidget.image) ||
        widget.pageWidth != oldWidget.pageWidth ||
        widget.pageHeight != oldWidget.pageHeight ||
        (widget.highlight != null && widget.highlight != oldWidget.highlight)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal();
      });
    }
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final resized = _size.width != box.maxWidth;
      _size = box.biggest;
      if (resized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reveal();
        });
      }
      return PageTurnGesture(
        key: ObjectKey(widget.image),
        axis: widget.turnAxis,
        canTurn: _atEdge,
        onTurn: (delta) => widget.onTurn?.call(delta),
        child: GestureDetector(
          onDoubleTap: fitWidth,
          child: ColoredBox(
            color: const Color(0xffdce1e8),
            child: InteractiveViewer(
              key: const Key('pdf-viewport'),
              transformationController: transform,
              constrained: false,
              alignment: Alignment.topLeft,
              boundaryMargin: const EdgeInsets.all(16),
              minScale: math.max(.01, math.min(_pageScale, _widthScale * .5)),
              maxScale: math.max(.02, _widthScale * 5),
              child: SizedBox(
                key: const Key('pdf-page-canvas'),
                width: widget.pageWidth,
                height: widget.pageHeight,
                child: PdfPageImage(
                  image: widget.image,
                  onPageTap: widget.onPageTap,
                  highlight: widget.highlight,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class PdfPageImage extends StatelessWidget {
  const PdfPageImage({
    super.key,
    required this.image,
    this.fit = BoxFit.fill,
    this.onPageTap,
    this.highlight,
  });

  final Future<Uint8List>? image;
  final BoxFit fit;
  final Rect? highlight;

  /// A touch point as fractions of the visible page from its top left.
  final ValueChanged<Offset>? onPageTap;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: FutureBuilder<Uint8List>(
      future: image,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: UiText(
                'Android не смог показать страницу. PDF может быть зашифрован или поврежден.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final png = snapshot.data!;
        Widget page = Image.memory(png, fit: fit, gaplessPlayback: false);
        if (highlight case final Rect bounds when png.length >= 24) {
          final header = ByteData.sublistView(png, 16, 24);
          final imageSize = Size(
            header.getUint32(0).toDouble(),
            header.getUint32(4).toDouble(),
          );
          page = CustomPaint(
            key: const Key('pdf-search-highlight'),
            foregroundPainter: _PdfMatchHighlight(bounds, imageSize, fit),
            child: page,
          );
        }
        final onTap = onPageTap;
        if (onTap == null) return page;
        return LayoutBuilder(
          builder: (_, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (event) {
              final point = event.localPosition;
              if (box.biggest.contains(point)) {
                onTap(
                  Offset(point.dx / box.maxWidth, point.dy / box.maxHeight),
                );
              }
            },
            child: page,
          ),
        );
      },
    ),
  );
}

class _PdfMatchHighlight extends CustomPainter {
  const _PdfMatchHighlight(this.bounds, this.imageSize, this.fit);

  final Rect bounds;
  final Size imageSize;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(fit, imageSize, size);
    final area = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        area.left + bounds.left * area.width,
        area.top + bounds.top * area.height,
        area.left + bounds.right * area.width,
        area.top + bounds.bottom * area.height,
      ),
      Paint()..color = const Color(0x66ffc107),
    );
  }

  @override
  bool shouldRepaint(_PdfMatchHighlight oldDelegate) =>
      bounds != oldDelegate.bounds ||
      imageSize != oldDelegate.imageSize ||
      fit != oldDelegate.fit;
}
