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
  _Session(this.bytes);
  final Uint8List bytes;
  int? native;
  Future<int>? fallback;
  bool closed = false;
}

/// Rust rasterization on the existing serial document worker, independent of
/// Android. The optional OS adapter remains a compatibility and offline OCR path.
final class NativePdfPageRenderer implements PdfPageRenderer {
  NativePdfPageRenderer({this.fallback, this.workerEntry = _pdfRasterWorker});
  final PdfPageRenderer? fallback;
  final DocumentWorkerEntry workerEntry;
  final _sessions = <int, _Session>{};
  DocumentWorker? _worker;
  int _next = 0, _opening = 0;
  int nativeRenders = 0, fallbackRenders = 0;

  @override
  bool get supportsOcr => fallback?.supportsOcr ?? false;

  _Session _get(int id) => _sessions[id] ??
      (throw StateError('PDF raster session is closed'));

  Future<int> _fallback(_Session session) async {
    final adapter = fallback;
    if (adapter == null) throw StateError('No PDF compatibility renderer');
    if (session.closed) throw StateError('PDF raster session is closed');
    final token = await (session.fallback ??= adapter.open(session.bytes));
    if (session.closed) throw StateError('PDF raster session is closed');
    return token;
  }

  Future<void> _idle() async {
    if (_sessions.isNotEmpty || _opening != 0) return;
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }

  @override
  Future<int> open(Uint8List pdf) async {
    if (pdf.length < 5 || pdf.length > 64 * 1024 * 1024 ||
        ascii.decode(pdf.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw const FormatException('Invalid PDF bytes');
    }
    final session = _Session(immutableDocumentBytes(pdf));
    final worker = _worker ??= DocumentWorker(workerEntry);
    _opening++;
    try {
      try {
        final bytes = await worker.request('raster', {'op': 'open', 'bytes': session.bytes}) as Uint8List;
        final info = jsonDecode(utf8.decode(bytes));
        if (info case {'session': int token, 'pageCount': int count}
            when token > 0 && count >= 1 && count <= 10000) {
          session.native = token;
        } else {
          throw const FormatException('Invalid native PDF session response');
        }
      } catch (_) {
        if (fallback == null) rethrow;
        await _fallback(session);
      }
      final id = ++_next;
      _sessions[id] = session;
      return id;
    } finally {
      _opening--;
      await _idle();
    }
  }

  @override
  Future<Uint8List> render(int session, int page, {int width = 1000}) async {
    if (page < 0 || width < 96 || width > 1600) {
      throw RangeError('Invalid PDF raster page/width');
    }
    final state = _get(session);
    if (state.native != null) {
      try {
        final png = await _worker!.request('raster', {
          'op': 'page', 'session': state.native, 'page': page, 'width': width,
        }) as Uint8List;
        if (state.closed) throw StateError('PDF raster session is closed');
        if (png.length < 24 || png.length > 24 * 1024 * 1024 ||
            png.take(8).join(',') != '137,80,78,71,13,10,26,10') {
          throw const FormatException('Invalid native PDF PNG');
        }
        final header = ByteData.sublistView(png);
        final w = header.getUint32(16), h = header.getUint32(20);
        if (w == 0 || h == 0 || w > 2880 || h > 2880 || w*h > 4200000) {
          throw const FormatException('Invalid native PDF raster dimensions');
        }
        nativeRenders++;
        return png;
      } catch (_) {
        if (fallback == null || state.closed) rethrow;
      }
    }
    final token = await _fallback(state);
    final png = await fallback!.render(token, page, width: width);
    if (state.closed) throw StateError('PDF raster session is closed');
    fallbackRenders++;
    return png;
  }

  @override
  Future<PdfOcrResult> recognize(int session, int page) async {
    if (page < 0) throw RangeError.value(page, 'page');
    final state = _get(session);
    final token = await _fallback(state);
    final result = await fallback!.recognize(token, page);
    if (state.closed) throw StateError('PDF raster session is closed');
    return result;
  }

  @override
  Future<void> close(int session) async {
    final state = _sessions.remove(session);
    if (state == null) return;
    state.closed = true;
    try {
      if (state.native != null) {
        await _worker!.request('raster', {'op': 'close', 'session': state.native});
      }
    } finally {
      try {
        if (state.fallback != null) {
          int? token;
          try { token = await state.fallback!; } catch (_) { /* Opening failed. */ }
          if (token != null) await fallback!.close(token);
        }
      } finally {
        await _idle();
      }
    }
  }
}
