import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_worker.dart';
import 'package:artofficecraft_mobile/native/native_pdf_image_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void worker((SendPort, Map<String, Object?>) args) {
  serveDocumentWorker(args.$1, (_, payload) {
    final p = payload as Map;
    if (p['library'] == 'missing') {
      throw const FormatException('No OCR library');
    }
    if (p['models'] != '/models' || (p['png'] as Uint8List).length != 24) {
      throw StateError('Invalid OCR request');
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'text': 'Русский English', 'words': []})),
    );
  });
}

void main() {
  test(
    'native OCR uses an owned worker and releases it after success or failure',
    () async {
      for (final library in ['bundled', 'missing', 'bundled']) {
        final ocr = NativePdfImageOcr(
          library: library,
          models: () async => '/models',
          workerEntry: worker,
        );
        if (library == 'missing') {
          await expectLater(
            ocr.recognize(Uint8List(24)),
            throwsFormatException,
          );
        } else {
          expect((await ocr.recognize(Uint8List(24))).text, 'Русский English');
        }
      }
    },
  );
  test(
    'invalid image length fails before model preparation or worker startup',
    () async {
      final ocr = NativePdfImageOcr(
        library: 'bundled',
        models: () async => throw StateError('Must not prepare models'),
        workerEntry: worker,
      );
      await expectLater(ocr.recognize(Uint8List(0)), throwsFormatException);
      await expectLater(
        ocr.recognize(Uint8List(24 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );
}
