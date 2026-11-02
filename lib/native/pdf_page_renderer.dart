import 'dart:io';

import 'package:flutter/services.dart';

/// Draws a PDF page locally using Android's built-in PdfRenderer (API 21+).
/// PDFCraft Rust stays responsible for document edits and saving new copies.
final class PdfPageRenderer {
  PdfPageRenderer({
    MethodChannel? channel,
    this._allowNonAndroidForTesting = false,
  }) : _channel = channel ?? const MethodChannel('artofficecraft/pdf_renderer');

  final MethodChannel _channel;
  final bool _allowNonAndroidForTesting;

  Future<Uint8List> render(Uint8List pdf, int page, {int width = 1000}) async {
    if (!Platform.isAndroid && !_allowNonAndroidForTesting) {
      throw UnsupportedError('PDF page rendering requires Android.');
    }
    if (pdf.isEmpty || pdf.length > 64 * 1024 * 1024) {
      throw const FormatException('Invalid PDF input size');
    }
    if (page < 0 || width < 96 || width > 1600) {
      throw RangeError('Invalid PDF page or render width');
    }
    final result = await _channel.invokeMethod<Uint8List>('renderPage', {
      'pdf': pdf,
      'page': page,
      'width': width,
    });
    if (result == null || result.isEmpty) {
      throw const FormatException('Android renderer returned no page image');
    }
    // The platform channel explicitly returns PNG bytes.
    const pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (result.length < pngHeader.length) {
      throw const FormatException('Invalid rendered image');
    }
    for (var i = 0; i < pngHeader.length; i++) {
      if (result[i] != pngHeader[i]) {
        throw const FormatException('Android renderer returned non-PNG data');
      }
    }
    return result;
  }
}
