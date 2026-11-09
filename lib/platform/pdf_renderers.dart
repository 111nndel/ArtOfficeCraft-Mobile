import '../native/pdf_page_renderer.dart';
import 'android_pdf_page_renderer.dart';

// A platform entry point may supply another implementation without changing
// the PDF editor. Android remains the only packaged renderer at present.
PdfPageRenderer createPdfPageRenderer() => AndroidPdfPageRenderer();
