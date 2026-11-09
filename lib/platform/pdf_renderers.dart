import 'dart:io';

import '../native/pdf_page_renderer.dart';
import '../native/native_pdf_page_renderer.dart';
import 'android_pdf_page_renderer.dart';

PdfPageRenderer createPdfPageRenderer() => NativePdfPageRenderer(
  fallback: Platform.isAndroid ? AndroidPdfPageRenderer() : null,
);
