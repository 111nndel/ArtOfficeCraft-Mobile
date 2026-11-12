import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'document_worker.dart';
import 'pdf_page_renderer.dart';
import 'pdfcraft_bridge.dart';

void _imageOcrWorker((SendPort, Map<String, Object?>) args) {
  serveDocumentWorker(args.$1, (_, payload) {
    final request = (payload as Map).cast<String, dynamic>();
    final png = request.remove('png') as Uint8List;
    final bridge = PdfCraftBridge.tryOpen();
    if (bridge == null) throw StateError('Native image OCR is unavailable');
    return bridge.recognizeImage(png, request);
  });
}

/// Recognition owns a short-lived worker and releases native OCR/model memory
/// when the request ends. Rendering remains on the independent PDF worker.
final class NativePdfImageOcr {
  NativePdfImageOcr({
    required this.library,
    required this.models,
    this.workerEntry = _imageOcrWorker,
  });
  final String library;
  final Future<String> Function() models;
  final DocumentWorkerEntry workerEntry;

  Future<PdfOcrResult> recognize(Uint8List png) async {
    if (png.length < 24 || png.length > 24 * 1024 * 1024) {
      throw const FormatException('Invalid OCR image length');
    }
    final directory = await models();
    final worker = DocumentWorker(workerEntry);
    try {
      final result = await worker.request('ocr', {
        'png': png,
        'library': library,
        'models': directory,
      }) as Uint8List;
      return parsePdfOcrResult(jsonDecode(utf8.decode(result)));
    } finally {
      await worker.close();
    }
  }
}
