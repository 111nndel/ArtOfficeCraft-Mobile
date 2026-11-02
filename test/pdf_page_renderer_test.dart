import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('artofficecraft/pdf_renderer');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('PDF render channel sends only local bytes, page and width', () async {
    final pdf = Uint8List.fromList(<int>[37, 80, 68, 70, 45]);
    final png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 1]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'renderPage');
          final params = Map<String, dynamic>.from(call.arguments as Map);
          expect(params.keys.toSet(), <String>{'pdf', 'page', 'width'});
          expect(params['pdf'], orderedEquals(pdf));
          expect(params['page'], 2);
          expect(params['width'], 480);
          return png;
        });
    final renderer = PdfPageRenderer(allowNonAndroidForTesting: true);
    final image = await renderer.render(pdf, 2, width: 480);
    expect(image, orderedEquals(png));
  });

  test(
    'Reject invalid page and oversized width before invoking Android',
    () async {
      final renderer = PdfPageRenderer(allowNonAndroidForTesting: true);
      final pdf = Uint8List.fromList(<int>[37, 80, 68, 70, 45]);
      await expectLater(renderer.render(pdf, -1), throwsRangeError);
      await expectLater(renderer.render(pdf, 0, width: 2000), throwsRangeError);
      await expectLater(
        renderer.render(Uint8List(0), 0),
        throwsFormatException,
      );
    },
  );

  test('Reject invalid PNG returned from native renderer', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Uint8List.fromList(<int>[65, 65, 65, 65, 65, 65, 65, 65, 65]);
        });
    final renderer = PdfPageRenderer(allowNonAndroidForTesting: true);
    await expectLater(
      renderer.render(Uint8List.fromList(<int>[37, 80, 68, 70, 45]), 0),
      throwsFormatException,
    );
  });
}
