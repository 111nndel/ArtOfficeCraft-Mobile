import 'dart:convert';

import 'package:artofficecraft_mobile/native/native_pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Rust FFI on Android renders the eight shared fidelity cases', (
    tester,
  ) async {
    // These assets are added only in the isolated fidelity job's debug build.
    final data = await rootBundle.load('assets/qa/pdf-fidelity.pdf');
    final pdf = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/qa/pdf-fidelity.json'),
    ) as Map;
    expect(pdf.length, manifest['pdfBytes']);
    final pages = manifest['pages'] as List;
    expect(pages, hasLength(8));
    final renderer = NativePdfPageRenderer();
    final images = <Map<String, Object>>[];
    final details = <Map<String, Object>>[];
    final session = await renderer.open(pdf);
    try {
      for (final entry in pages) {
        final page = entry as Map;
        final number = page['page'] as int;
        final size = (page['size'] as List).cast<int>();
        final png = await renderer.render(session, number - 1, width: size[0]);
        final header = ByteData.sublistView(png);
        expect(header.getUint32(16), size[0]);
        expect(header.getUint32(20), size[1]);
        images.add({
          'renderer': 'rust-android',
          'page': number,
          'width': size[0],
          'height': size[1],
          'png': base64Encode(png),
        });
      }
      for (final raw in manifest['tiles'] as List) {
        final tile = raw as Map;
        final request = (
          pageWidth: tile['pageWidth'] as int,
          x: tile['x'] as int,
          y: tile['y'] as int,
          width: tile['width'] as int,
          height: tile['height'] as int,
        );
        final page = (tile['page'] as int) - 1;
        final png = await renderer.renderTile(session, page, request);
        final header = ByteData.sublistView(png);
        expect(header.getUint32(16), request.width);
        expect(header.getUint32(20), request.height);
        final preview = await renderer.render(session, page, width: 1000);
        details.add({
          'renderer': 'rust-android',
          'name': tile['name'] as String,
          'png': base64Encode(png),
          'preview': base64Encode(preview),
        });
      }
      expect(renderer.nativeRenders, 14);
      final key = GlobalKey<PdfViewportState>();
      final preview = await renderer.render(session, 0);
      final requests = <PdfPageTile>[];
      final completedWidths = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewport(
              key: key,
              image: Future.value(preview),
              pageWidth: 600,
              pageHeight: 800,
              pageIdentity: 'fidelity-zoom',
              renderTile: (tile) async {
                requests.add(tile);
                final png = await renderer.renderTile(session, 0, tile);
                completedWidths.add(tile.pageWidth);
                return png;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scale = key.currentState!.transform.value.getMaxScaleOnAxis() * 4;
      final position = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(2, 2, scale)
        ..setTranslationRaw(-400, -500, 0);
      key.currentState!.transform.value = position;
      await tester.pump(const Duration(milliseconds: 250));
      for (
        var i = 0;
        i < 100 && !completedWidths.any((width) => width > 3000);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('pdf-page-detail')), findsOneWidget);
      expect(requests.last.pageWidth, greaterThan(3000));
      expect(completedWidths.any((width) => width > 3000), isTrue);
      expect(key.currentState!.transform.value, position);
      final detail = find.descendant(
        of: find.byKey(const Key('pdf-page-detail')),
        matching: find.byType(RawImage),
      );
      // The worker result arrives before Flutter finishes decoding its PNG.
      // Capture the displayed detail rather than the retained preview.
      for (var i = 0; i < 100; i++) {
        final pixels = tester.widget<RawImage>(detail).image;
        if (pixels?.width == requests.last.width &&
            pixels?.height == requests.last.height) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      final pixels = tester.widget<RawImage>(detail).image;
      expect(pixels?.width, requests.last.width);
      expect(pixels?.height, requests.last.height);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('pdf-detail-zoom-055');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await renderer.close(session);
    }
    expect(renderer.nativeRenders, greaterThanOrEqualTo(15));
    binding.reportData = {
      ...?binding.reportData,
      'rasters': images,
      'tiles': details,
      'fixtureSha256': manifest['pdfSha256'],
    };
  });
}
