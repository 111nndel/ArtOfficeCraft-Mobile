import 'dart:io';

import 'package:artofficecraft_mobile/native/native_pdf_image_ocr.dart';
import 'package:artofficecraft_mobile/native/native_pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/native/pdfcraft_bridge.dart';

Future<void> main(List<String> args) async {
  final bridge = PdfCraftBridge.tryOpen();
  if (bridge == null || args.length != 2) {
    throw StateError('Supply bundled core, Tesseract and model directory');
  }
  final document = bridge.edit(bridge.create(), {
    'action': 'insert_text',
    'page': 0,
    'x': 0.08,
    'y': 0.1,
    'size': 36,
    'text': 'ПРОВЕРКА ТЕКСТА\nOFFLINE TEST',
  });
  final renderer = NativePdfPageRenderer();
  final session = await renderer.open(document);
  try {
    final png = await renderer.render(session, 0, width: 1440);
    final ocr = NativePdfImageOcr(
      library: args[0],
      models: () async => args[1],
    );
    for (var i = 0; i < 2; i++) {
      final result = await ocr.recognize(png);
      if (!result.text.contains('ПРОВЕРКА ТЕКСТА') ||
          !result.text.contains('OFFLINE TEST') ||
          result.words.isEmpty) {
        throw StateError('Russian/English native OCR failed: ${result.text}');
      }
    }
    stdout.writeln(
      'PASS image OCR: Linux AOT worker, Rust PNG decoder, Tesseract C API, Russian/English and repeated cleanup',
    );
  } finally {
    await renderer.close(session);
  }
}
