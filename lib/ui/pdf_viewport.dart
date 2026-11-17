import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../native/pdf_page_renderer.dart';
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
    this.renderTile,
  });
  final Future<Uint8List>? image;
  final double pageWidth, pageHeight;
  final Axis? turnAxis;
  final ValueChanged<int>? onTurn;
  final ValueChanged<Offset>? onPageTap;
  final Object? pageIdentity;
  final Rect? highlight;
  final PdfTileRaster? renderTile;
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
                child: AnimatedBuilder(
                  animation: transform,
                  builder: (context, _) => PdfPageImage(
                    image: widget.image,
                    pageSize: Size(widget.pageWidth, widget.pageHeight),
                    pageIdentity: widget.pageIdentity ?? widget.image,
                    renderTile: widget.renderTile,
                    view: (
                      viewport: Rect.fromPoints(
                        transform.toScene(Offset.zero),
                        transform.toScene(Offset(_size.width, _size.height)),
                      ),
                      pixelRatio:
                          transform.value.getMaxScaleOnAxis() *
                          MediaQuery.devicePixelRatioOf(context),
                    ),
                    onPageTap: widget.onPageTap,
                    highlight: widget.highlight,
                  ),
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
    this.pageSize,
    this.view,
    this.renderTile,
    this.pageIdentity,
  });

  final Future<Uint8List>? image;
  final BoxFit fit;
  final Rect? highlight;
  final Size? pageSize;
  final PageRasterView? view;
  final PdfTileRaster? renderTile;
  final Object? pageIdentity;

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
        if (renderTile != null && view != null && pageSize != null) {
          page = _PdfPageDetail(
            key: ValueKey(pageIdentity ?? image),
            preview: png,
            pageSize: pageSize!,
            view: view!,
            render: renderTile!,
            fit: fit,
          );
        }
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

/// A single viewport-sized detail image over the retained page preview.
/// Gesture frames only update demand; one render runs at a time after settling.
class _PdfPageDetail extends StatefulWidget {
  const _PdfPageDetail({
    super.key,
    required this.preview,
    required this.pageSize,
    required this.view,
    required this.render,
    required this.fit,
  });
  final Uint8List preview;
  final Size pageSize;
  final PageRasterView view;
  final PdfTileRaster render;
  final BoxFit fit;

  @override
  State<_PdfPageDetail> createState() => _PdfPageDetailState();
}

class _PdfPageDetailState extends State<_PdfPageDetail> {
  Timer? _debounce;
  PdfPageTile? _wanted, _active, _failed;
  ({PdfPageTile tile, Uint8List png})? _detail;
  int _generation = 0;

  void _evict(Uint8List? png) {
    if (png != null) unawaited(MemoryImage(png).evict());
  }

  @override
  void didUpdateWidget(covariant _PdfPageDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.preview, oldWidget.preview) ||
        widget.pageSize != oldWidget.pageSize) {
      _generation++;
      _debounce?.cancel();
      _debounce = null;
      _wanted = _failed = null;
      _evict(_detail?.png);
      _detail = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _evict(_detail?.png);
    super.dispose();
  }

  void _demand(PdfPageTile? tile) {
    if (_wanted == tile) return;
    _wanted = tile;
    if (_failed != tile) _failed = null;
    _debounce?.cancel();
    _debounce = null;
    if (tile != null &&
        tile != _detail?.tile &&
        tile != _active &&
        tile != _failed) {
      _debounce = Timer(const Duration(milliseconds: 160), _render);
    }
  }

  Future<void> _render() async {
    _debounce = null;
    final tile = _wanted;
    if (_active != null ||
        tile == null ||
        tile == _detail?.tile ||
        tile == _failed)
      return;
    _active = tile;
    final generation = _generation;
    try {
      final png = await widget.render(tile);
      if (!mounted || generation != _generation || _wanted != tile) return;
      final previous = _detail?.png;
      setState(() => _detail = (tile: tile, png: png));
      if (!identical(previous, png)) _evict(previous);
    } catch (_) {
      if (mounted && generation == _generation && _wanted == tile)
        _failed = tile;
      // Keep the preview and any previous detail while compatibility is unavailable.
    } finally {
      _active = null;
      if (mounted &&
          _wanted != null &&
          _wanted != _detail?.tile &&
          _wanted != _failed) {
        _debounce ??= Timer(const Duration(milliseconds: 160), _render);
      }
    }
  }

  PdfPageTile? _request(Rect visible, double aspect, double pixels) {
    if (!pixels.isFinite || pixels <= 0 || !aspect.isFinite || aspect <= 0)
      return null;
    var full = ((pixels / 128).ceil() * 128).clamp(96, maxPdfTilePageWidth);
    final previewWidth = widget.preview.length >= 24
        ? ByteData.sublistView(widget.preview).getUint32(16)
        : 1000;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (full <= previewWidth) return null;
      final fullHeight = (full * aspect).floor().clamp(1, 0x7fffffff);
      const pad = 96;
      final left = math.max(0, ((visible.left * full - pad) / 64).floor() * 64);
      final top = math.max(
        0,
        ((visible.top * full * aspect - pad) / 64).floor() * 64,
      );
      final right = math.min(
        full,
        ((visible.right * full + pad) / 64).ceil() * 64,
      );
      final bottom = math.min(
        fullHeight,
        ((visible.bottom * full * aspect + pad) / 64).ceil() * 64,
      );
      final width = right - left, height = bottom - top;
      if (width <= 0 || height <= 0) return null;
      if (width <= maxPdfRasterSide &&
          height <= maxPdfRasterSide &&
          width * height <= maxPdfRasterPixels) {
        return (pageWidth: full, x: left, y: top, width: width, height: height);
      }
      final reduction = math.min(
        math.min(maxPdfRasterSide / width, maxPdfRasterSide / height),
        math.sqrt(maxPdfRasterPixels / (width * height)),
      );
      full = (full * reduction * .96).floor().clamp(96, maxPdfTilePageWidth);
    }
    return null;
  }

  bool _covers(PdfPageTile? tile, Rect visible, double aspect, int width) =>
      tile != null &&
      tile.pageWidth >= width &&
      tile.x <= visible.left * tile.pageWidth + 1 &&
      tile.y <= visible.top * tile.pageWidth * aspect + 1 &&
      tile.x + tile.width >= visible.right * tile.pageWidth - 1 &&
      tile.y + tile.height >= visible.bottom * tile.pageWidth * aspect - 1;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final page = Alignment.center.inscribe(
        applyBoxFit(widget.fit, widget.pageSize, box.biggest).destination,
        Offset.zero & box.biggest,
      );
      final visible = widget.view.viewport.intersect(page);
      PdfPageTile? wanted;
      if (!visible.isEmpty && page.width > 0 && page.height > 0) {
        final region = Rect.fromLTRB(
          (visible.left - page.left) / page.width,
          (visible.top - page.top) / page.height,
          (visible.right - page.left) / page.width,
          (visible.bottom - page.top) / page.height,
        );
        final aspect = widget.pageSize.height / widget.pageSize.width;
        wanted = _request(region, aspect, page.width * widget.view.pixelRatio);
        if (wanted != null) {
          if (_covers(_detail?.tile, region, aspect, wanted.pageWidth)) {
            wanted = _detail!.tile;
          } else if (_covers(_active, region, aspect, wanted.pageWidth)) {
            wanted = _active;
          }
        }
      }
      _demand(wanted);
      final detail = _detail;
      final unit = detail == null ? 0.0 : page.width / detail.tile.pageWidth;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(widget.preview, fit: widget.fit),
          if (detail != null)
            Positioned(
              left: page.left + detail.tile.x * unit,
              top: page.top + detail.tile.y * unit,
              width: detail.tile.width * unit,
              height: detail.tile.height * unit,
              child: Image.memory(
                detail.png,
                key: const Key('pdf-page-detail'),
                fit: BoxFit.fill,
              ),
            ),
        ],
      );
    },
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
