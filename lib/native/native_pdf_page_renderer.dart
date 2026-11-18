import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'document_backend.dart' show immutableDocumentBytes;
import 'document_worker.dart';
import 'pdf_page_renderer.dart';
import 'pdfcraft_bridge.dart';

void _pdfRasterWorker((SendPort, Map<String, Object?>) args) {
  PdfCraftBridge? bridge;
  serveDocumentWorker(args.$1, (operation, payload) {
    bridge ??= PdfCraftBridge.tryOpen();
    final engine = bridge;
    if (engine == null) throw StateError('Native PDF renderer is unavailable');
    final request = (payload as Map).cast<String, dynamic>();
    final input = request.remove('bytes') as Uint8List? ?? Uint8List(0);
    return engine.raster(input, request);
  });
}

class _Session {
  _Session(this.native);
  final int native;
  bool closed = false;
}

/// Portable Rust rasterization on the serial document worker; image OCR is injectable.
final class NativePdfPageRenderer implements PdfPageRenderer, PdfTileRenderer {
  NativePdfPageRenderer({
    this.recognizeImage,
    this.workerEntry = _pdfRasterWorker,
  });
  final PdfImageOcr? recognizeImage;
  final DocumentWorkerEntry workerEntry;
  final _sessions = <int, _Session>{};
  DocumentWorker? _worker;
  int _next = 0, _opening = 0;
  int nativeRenders = 0;

  @override
  bool get supportsOcr => recognizeImage != null;

  _Session _get(int id) =>
      _sessions[id] ?? (throw StateError('PDF raster session is closed'));

  Future<void> _idle() async {
    if (_sessions.isNotEmpty || _opening != 0) return;
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }

  @override
  Future<int> open(Uint8List pdf) async {
    if (pdf.length < 5 ||
        pdf.length > 64 * 1024 * 1024 ||
        ascii.decode(pdf.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw const FormatException('Invalid PDF bytes');
    }
    final worker = _worker ??= DocumentWorker(workerEntry);
    _opening++;
    try {
      final bytes = await worker.request('raster', {
        'op': 'open',
        'bytes': immutableDocumentBytes(pdf),
      }) as Uint8List;
      final info = jsonDecode(utf8.decode(bytes));
      if (info case {'session': int token, 'pageCount': int count}
          when token > 0 && count >= 1 && count <= 10000) {
        final id = ++_next;
        _sessions[id] = _Session(token);
        return id;
      }
      throw const FormatException('Invalid native PDF session response');
    } finally {
      _opening--;
      await _idle();
    }
  }

  @override
  Future<Uint8List> render(int session, int page, {int width = 1000}) =>
      _render(session, page, width: width);

  @override
  Future<Uint8List> renderTile(int session, int page, PdfPageTile tile) async {
    pdfTileArguments(tile);
    return _render(session, page, width: tile.pageWidth, tile: tile);
  }

  Future<Uint8List> _render(
    int session,
    int page, {
    required int width,
    PdfPageTile? tile,
  }) async {
    if (page < 0 ||
        width < 96 ||
        width > (tile == null ? 1600 : maxPdfTilePageWidth)) {
      throw RangeError('Invalid PDF raster page/width');
    }
    final state = _get(session);
    final png = await _worker!.request('raster', {
      'op': tile == null ? 'page' : 'tile',
      'session': state.native,
      'page': page,
      'width': width,
      if (tile != null) 'tile': [tile.x, tile.y, tile.width, tile.height],
    }) as Uint8List;
    if (state.closed) throw StateError('PDF raster session is closed');
    if (png.length < 24 ||
        png.length > 24 * 1024 * 1024 ||
        png.take(8).join(',') != '137,80,78,71,13,10,26,10') {
      throw const FormatException('Invalid native PDF PNG');
    }
    final header = ByteData.sublistView(png);
    final w = header.getUint32(16), h = header.getUint32(20);
    if (w == 0 ||
        h == 0 ||
        w > maxPdfRasterSide ||
        h > maxPdfRasterSide ||
        w * h > maxPdfRasterPixels ||
        (tile != null && (w != tile.width || h != tile.height))) {
      throw const FormatException('Invalid native PDF raster dimensions');
    }
    nativeRenders++;
    return png;
  }

  @override
  Future<PdfOcrResult> recognize(int session, int page) async {
    if (page < 0) throw RangeError.value(page, 'page');
    final state = _get(session);
    final recognize = recognizeImage;
    if (recognize == null) {
      throw UnsupportedError('Page image OCR is unavailable');
    }
    final png = await render(session, page, width: 1440);
    if (state.closed) throw StateError('PDF raster session is closed');
    final result = await recognize(png);
    if (state.closed) throw StateError('PDF raster session is closed');
    return result;
  }

  @override
  Future<void> close(int session) async {
    final state = _sessions.remove(session);
    if (state == null) return;
    state.closed = true;
    try {
      await _worker!.request('raster', {
        'op': 'close',
        'session': state.native,
      });
    } finally {
      await _idle();
    }
  }
}
