import 'dart:typed_data';

typedef PdfOcrWord = ({String text, List<double> rect});
typedef PdfOcrResult = ({String text, List<PdfOcrWord> words});

/// Page rasterization and offline OCR are independent of PDFCraft editing.
/// The owner closes every opened session, including replaced documents.
abstract interface class PdfPageRenderer {
  bool get supportsOcr;
  Future<int> open(Uint8List pdf);
  Future<Uint8List> render(int session, int page, {int width = 1000});
  Future<PdfOcrResult> recognize(int session, int page);
  Future<void> close(int session);
}
