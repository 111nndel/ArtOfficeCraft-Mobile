import 'dart:typed_data';

typedef PdfOcrWord = ({String text, List<double> rect});
typedef PdfOcrResult = ({String text, List<PdfOcrWord> words});

/// Recognizes a bounded page PNG without opening or parsing a PDF.
typedef PdfImageOcr = Future<PdfOcrResult> Function(Uint8List png);

/// Page rasterization and offline OCR are independent of PDFCraft editing.
/// The owner closes every opened session, including replaced documents.
abstract interface class PdfPageRenderer {
  bool get supportsOcr;
  Future<int> open(Uint8List pdf);
  Future<Uint8List> render(int session, int page, {int width = 1000});
  Future<PdfOcrResult> recognize(int session, int page);
  Future<void> close(int session);
}

/// Validate native or injected OCR results at the shared Dart boundary.
PdfOcrResult parsePdfOcrResult(Object? result) {
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
