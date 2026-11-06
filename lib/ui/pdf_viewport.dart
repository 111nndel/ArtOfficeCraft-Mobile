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
  });
  final Future<Uint8List>? image;
  final double pageWidth, pageHeight;
  final Axis? turnAxis;
  final ValueChanged<int>? onTurn;
  final ValueChanged<Offset>? onPageTap;
  final Object? pageIdentity;
  @override
  State<PdfViewport> createState() => PdfViewportState();
}

class PdfViewportState extends State<PdfViewport> {
  final transform = TransformationController();
  Size _size = Size.zero;
  double get _widthScale => (_size.width - 16) / widget.pageWidth;
  double get _pageScale =>
      math.min(_widthScale, (_size.height - 16) / widget.pageHeight);
  void _fit(double scale) {
    if (!scale.isFinite || scale <= 0) return;
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setTranslationRaw((_size.width - widget.pageWidth * scale) / 2, 8, 0);
  }

  void fitWidth() => _fit(_widthScale);
  void fitPage() => _fit(_pageScale);

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
        widget.pageHeight != oldWidget.pageHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitWidth();
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
          if (mounted) fitWidth();
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
  });

  final Future<Uint8List>? image;
  final BoxFit fit;

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
        final page = Image.memory(
          snapshot.data!,
          fit: fit,
          gaplessPlayback: false,
        );
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
