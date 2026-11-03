import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// The viewport fills the available canvas. The page starts fitted to width,
/// even when it is taller than the screen, and remains pannable at every scale.
class PdfViewport extends StatefulWidget {
  const PdfViewport({
    super.key,
    required this.image,
    required this.pageWidth,
    required this.pageHeight,
  });
  final Future<Uint8List>? image;
  final double pageWidth, pageHeight;
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
  @override
  void didUpdateWidget(covariant PdfViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image ||
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
      return GestureDetector(
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
              child: ColoredBox(
                color: Colors.white,
                child: FutureBuilder<Uint8List>(
                  future: widget.image,
                  builder: (context, snapshot) {
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
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.fill,
                      gaplessPlayback: false,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
