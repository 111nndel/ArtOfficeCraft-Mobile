import 'dart:typed_data';

typedef PdfOcrWord = ({String text, List<double> rect});
typedef PdfOcrResult = ({String text, List<PdfOcrWord> words});

/// Recognizes a bounded page PNG without opening or parsing a PDF.
typedef PdfImageOcr = Future<PdfOcrResult> Function(Uint8List png);

/// Device-pixel coordinates on a page rendered at the requested `pageWidth`.
typedef PdfPageTile = ({int pageWidth, int x, int y, int width, int height});
typedef PdfTileRaster = Future<Uint8List> Function(PdfPageTile tile);
const maxPdfRasterSide = 2880;
const maxPdfRasterPixels = 4200000;
const maxPdfTilePageWidth = 16384;

/// Optional detail rendering; existing preview/OCR adapters remain independent.
abstract interface class PdfTileRenderer {
  Future<Uint8List> renderTile(int session, int page, PdfPageTile tile);
}

Map<String, Object> pdfTileArguments(PdfPageTile tile) {
  if (tile.pageWidth < 96 ||
      tile.pageWidth > maxPdfTilePageWidth ||
      tile.x < 0 ||
      tile.y < 0 ||
      tile.y > 0x7fffffff ||
      tile.width < 1 ||
      tile.height < 1 ||
      tile.width > maxPdfRasterSide ||
      tile.height > maxPdfRasterSide ||
      tile.width * tile.height > maxPdfRasterPixels ||
      tile.x + tile.width > tile.pageWidth ||
      tile.y + tile.height > 0x7fffffff) {
    throw RangeError('Invalid PDF detail tile');
  }
  return {
    'width': tile.pageWidth,
    'tile': [tile.x, tile.y, tile.width, tile.height],
  };
}

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
