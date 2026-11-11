import 'dart:io';

import '../native/pdf_page_renderer.dart';

import 'package:flutter/services.dart';

/// Android first-party PdfRenderer with one open, app-private document session.
/// Used only when the Rust renderer cannot render a document or page.
final class AndroidPdfPageRenderer implements PdfPageRenderer {
  AndroidPdfPageRenderer({
    MethodChannel? channel,
    this.allowNonAndroidForTesting = false,
  }) : _channel = channel ?? const MethodChannel('artofficecraft/pdf_renderer');

  final MethodChannel _channel;
  final bool allowNonAndroidForTesting;

  @override
  bool get supportsOcr => false;

  void _platformCheck() {
    if (!Platform.isAndroid && !allowNonAndroidForTesting) {
      throw UnsupportedError('PDF rendering requires Android');
    }
  }

  @override
  Future<int> open(Uint8List pdf) async {
    _platformCheck();
    if (pdf.length < 5 ||
        pdf.length > 64 * 1024 * 1024 ||
        pdf[0] != 37 ||
        pdf[1] != 80 ||
        pdf[2] != 68 ||
        pdf[3] != 70 ||
        pdf[4] != 45) {
      throw const FormatException('Invalid PDF bytes');
    }
    final info = await _channel.invokeMapMethod<String, dynamic>(
      'openDocument',
      <String, Object>{'pdf': pdf},
    );
    final session = info?['session'];
    final pageCount = info?['pageCount'];
    if (session is! int ||
        session <= 0 ||
        pageCount is! int ||
        pageCount < 1 ||
        pageCount > 10000) {
      throw const FormatException('Invalid Android PDF session response');
    }
    return session;
  }

  @override
  Future<Uint8List> render(int session, int page, {int width = 1000}) async {
    _platformCheck();
    if (session <= 0 || page < 0 || width < 96 || width > 1600) {
      throw RangeError('Invalid PDF session/page/width');
    }
    final data = await _channel.invokeMethod<Uint8List>(
      'renderPage',
      <String, Object>{'session': session, 'page': page, 'width': width},
    );
    const header = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (data == null || data.length < header.length) {
      throw const FormatException('Android renderer returned no PNG');
    }
    for (var i = 0; i < header.length; i++) {
      if (data[i] != header[i]) {
        throw const FormatException('Android renderer returned non-PNG data');
      }
    }
    return data;
  }

  @override
  Future<PdfOcrResult> recognize(int session, int page) async =>
      throw UnsupportedError('Use page image OCR');

  @override
  Future<void> close(int session) async {
    _platformCheck();
    if (session <= 0) return;
    await _channel.invokeMethod<void>('closeDocument', <String, Object>{
      'session': session,
    });
  }
}
