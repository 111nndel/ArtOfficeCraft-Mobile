import 'dart:convert';

import 'package:artofficecraft_mobile/platform/android_pdf_page_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android PdfRenderer renders the six shared fidelity cases', (tester) async {
    // These assets are added only in the isolated fidelity job's debug build.
    final data = await rootBundle.load('assets/qa/pdf-fidelity.pdf');
    final pdf = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final manifest = jsonDecode(await rootBundle.loadString('assets/qa/pdf-fidelity.json')) as Map;
    expect(pdf.length, manifest['pdfBytes']);
    final pages = manifest['pages'] as List;
    expect(pages, hasLength(6));
    final renderer = AndroidPdfPageRenderer();
    final session = await renderer.open(pdf);
    final images = <Map<String, Object>>[];
    try {
      for (final entry in pages) {
        final page = entry as Map;
        final number = page['page'] as int;
        final size = (page['size'] as List).cast<int>();
        final png = await renderer.render(session, number - 1, width: size[0]);
        final header = ByteData.sublistView(png);
        expect(header.getUint32(16), size[0]);
        expect(header.getUint32(20), size[1]);
        images.add({'page': number, 'width': size[0], 'height': size[1], 'png': base64Encode(png)});
      }
    } finally {
      await renderer.close(session);
    }
    binding.reportData = {'rasters': images, 'fixtureSha256': manifest['pdfSha256']};
  });
}
