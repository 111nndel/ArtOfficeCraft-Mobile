import 'package:artofficecraft_mobile/platform/android_pdf_page_renderer.dart';
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
