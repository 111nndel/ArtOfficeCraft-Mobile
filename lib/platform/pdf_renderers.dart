import 'dart:io';

import '../native/pdf_page_renderer.dart';
import '../native/native_pdf_page_renderer.dart';
import 'android_pdf_page_renderer.dart';
import 'bundled_pdf_image_ocr.dart';
import 'application_storage.dart';

PdfPageRenderer createPdfPageRenderer({
  ApplicationStorage storage = const AndroidApplicationStorage(),
}) => NativePdfPageRenderer(
  fallback: Platform.isAndroid ? AndroidPdfPageRenderer() : null,
  recognizeImage: Platform.isAndroid
      ? bundledPdfImageOcr(storage).recognize
      : null,
);
