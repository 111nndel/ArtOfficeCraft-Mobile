import 'package:artofficecraft_mobile/platform/android_pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('artofficecraft/pdf_renderer');
  final pdf = Uint8List.fromList(<int>[37, 80, 68, 70, 45, 49, 46, 52]);
  final png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 1]);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Open once, render different pages, then close without resending bytes',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            final parameters = Map<String, dynamic>.from(call.arguments as Map);
            if (call.method == 'openDocument') {
              expect(parameters.keys.toSet(), <String>{'pdf'});
              expect(parameters['pdf'], orderedEquals(pdf));
              return <String, int>{'session': 52, 'pageCount': 3};
            }
            if (call.method == 'renderPage') {
              expect(parameters.keys.toSet(), <String>{
                'session',
                'page',
                'width',
              });
              expect(parameters['session'], 52);
              expect(parameters['width'], 480);
              expect(parameters['page'], calls.length == 2 ? 0 : 2);
              return png;
            }
            if (call.method == 'closeDocument') {
              expect(parameters, <String, int>{'session': 52});
              return null;
            }
            throw StateError('Unexpected channel action: ${call.method}');
          });
      final renderer = AndroidPdfPageRenderer(allowNonAndroidForTesting: true);
      final session = await renderer.open(pdf);
      expect(session, 52);
      expect(await renderer.render(session, 0, width: 480), orderedEquals(png));
      expect(await renderer.render(session, 2, width: 480), orderedEquals(png));
      await renderer.close(session);
      expect(calls, <String>[
        'openDocument',
        'renderPage',
        'renderPage',
        'closeDocument',
      ]);
    },
  );

  test('Reject invalid PDF, session, page, and raster width', () async {
    final renderer = AndroidPdfPageRenderer(allowNonAndroidForTesting: true);
    await expectLater(renderer.open(Uint8List(0)), throwsFormatException);
    await expectLater(
      renderer.open(Uint8List.fromList(<int>[1, 2, 3, 4, 5])),
      throwsFormatException,
    );
    await expectLater(renderer.render(-1, 0), throwsRangeError);
    await expectLater(renderer.render(1, -1), throwsRangeError);
    await expectLater(renderer.render(1, 0, width: 2000), throwsRangeError);
  });

  test(
    'detail crop uses the existing channel and validates returned dimensions',
    () async {
      const tile = (pageWidth: 6000, x: 1200, y: 2400, width: 320, height: 480);
      final data = Uint8List(24)..setAll(0, png.take(8));
      ByteData.sublistView(data)
        ..setUint32(16, 320)
        ..setUint32(20, 480);
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            expect(call.method, 'renderPage');
            expect(call.arguments, {
              'session': 5,
              'page': 2,
              ...pdfTileArguments(tile),
            });
            return data;
          });
      final renderer = AndroidPdfPageRenderer(allowNonAndroidForTesting: true);
      expect(await renderer.renderTile(5, 2, tile), data);
      ByteData.sublistView(data).setUint32(16, 321);
      await expectLater(renderer.renderTile(5, 2, tile), throwsFormatException);
      expect(calls, 2);
      await expectLater(
        renderer.renderTile(5, 2, (
          pageWidth: 6000,
          x: 0,
          y: 0,
          width: 2880,
          height: 2880,
        )),
        throwsRangeError,
      );
      expect(calls, 2);
    },
  );

  test('Reject invalid session response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, int>{'session': 0, 'pageCount': 100};
        });
    final renderer = AndroidPdfPageRenderer(allowNonAndroidForTesting: true);
    await expectLater(renderer.open(pdf), throwsFormatException);
  });

  test('Reject non-PNG bytes returned by Android', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Uint8List.fromList(<int>[
            65,
            65,
            65,
            65,
            65,
            65,
            65,
            65,
            65,
            65,
            65,
          ]);
        });
    final renderer = AndroidPdfPageRenderer(allowNonAndroidForTesting: true);
    await expectLater(renderer.render(5, 0), throwsFormatException);
  });
}
