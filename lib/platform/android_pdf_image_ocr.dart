import 'package:flutter/services.dart';

import '../native/pdf_page_renderer.dart';

/// Tesseract consumes the rendered image; no Android PDF session is involved.
Future<PdfOcrResult> recognizeAndroidPdfImage(Uint8List png) async {
  final result = await const MethodChannel('artofficecraft/pdf_ocr')
      .invokeMapMethod<String, Object?>('recognizeImage', {'png': png});
  if (result case {'text': String text, 'words': List rawWords}
      when text.length <= 64 * 1024 && rawWords.length <= 4096) {
    final words = <PdfOcrWord>[];
    var characters = 0;
    for (final entry in rawWords) {
      if (entry case {'text': String word, 'rect': List rect}
          when word.isNotEmpty &&
              rect.length == 4 &&
              rect.every((n) => n is num && n.isFinite && n >= 0 && n <= 1) &&
              (rect[0] as num) < (rect[2] as num) &&
              (rect[1] as num) < (rect[3] as num)) {
        characters += word.length;
        if (characters > 64 * 1024) {
          throw const FormatException('Too much OCR word text');
        }
        words.add((
          text: word,
          rect: rect.cast<num>().map((n) => n.toDouble()).toList(),
        ));
      } else {
        throw const FormatException('Invalid OCR word or bounds');
      }
    }
    return (text: text.trim(), words: words);
  }
  throw const FormatException('Invalid image OCR response');
}
