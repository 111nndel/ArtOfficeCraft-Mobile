import 'package:artofficecraft_mobile/platform/android_clipboard.dart';
import 'package:artofficecraft_mobile/native/grid_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final clipboard = GridClipboard(const AndroidSystemClipboard());
  Map<String, dynamic>? system;
  var failWrite = false;
  GridClip clip({String text = '10\t20'}) => GridClip(
    Uint8List.fromList([1, 2, 3]),
    0,
    {'range': 'A1:B1', 'rows': 1, 'columns': 2, 'text': text},
  );
  setUp(() {
    system = null;
    failWrite = false;
    clipboard.clearLocal();
    messenger.setMockMethodCallHandler(AndroidSystemClipboard.channel, (call) async {
      if (call.method == 'write') {
        if (failWrite) throw PlatformException(code: 'unavailable');
        system = Map<String, dynamic>.from(call.arguments as Map);
        return null;
      }
      return system;
    });
  });
  tearDown(() {
    clipboard.clearLocal();
    messenger.setMockMethodCallHandler(AndroidSystemClipboard.channel, null);
  });
  test('snapshot is immutable and Android receives only selected text and identity', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final entry = GridClip(bytes, 0, {
      'range': 'A1',
      'rows': 1,
      'columns': 1,
      'text': 'Selected',
    });
    bytes[0] = 9;
    expect(entry.source[0], 1);
    expect(() => entry.source[0] = 9, throwsUnsupportedError);
    await clipboard.write(entry);
    expect(system!.keys, unorderedEquals(['text', 'token']));
    expect(system!['text'], 'Selected');
    expect((await clipboard.read())!.rich, same(entry));
  });
  test(
    'equal external text never reuses rich source without matching identity',
    () async {
      final entry = clip();
      await clipboard.write(entry);
      system = {'text': entry.text};
      expect((await clipboard.read())!.rich, isNull);
      expect(clipboard.current, isNull);
      await clipboard.write(entry);
      system!['token'] = '0' * 32;
      expect((await clipboard.read())!.rich, isNull);
    },
  );
  test('changed text invalidates even a matching identity', () async {
    await clipboard.write(clip());
    system!['text'] = 'different';
    expect((await clipboard.read())!.text, 'different');
    expect(clipboard.current, isNull);
  });
  test('hidden-only rich range works with empty selected text', () async {
    final entry = clip(text: '');
    await clipboard.write(entry);
    expect((await clipboard.read())!.rich, same(entry));
    system = {'text': ''};
    expect(await clipboard.read(), isNull);
  });
  test('failed Android write leaves prior snapshot available', () async {
    final first = clip();
    await clipboard.write(first);
    failWrite = true;
    await expectLater(
      clipboard.write(clip(text: 'new')),
      throwsA(isA<PlatformException>()),
    );
    expect((await clipboard.read())!.rich, same(first));
  });
  test('dimension mismatch and oversized Unicode text are rejected', () async {
    expect(
      () => GridClip(Uint8List(1), 0, {
        'range': 'A1:B1',
        'rows': 2,
        'columns': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => clip(text: 'я' * (GridClip.maxText ~/ 2 + 1)),
      throwsFormatException,
    );
    system = {'text': 'я' * (GridClip.maxText ~/ 2 + 1)};
    await expectLater(clipboard.read(), throwsFormatException);
    expect(clipboard.current, isNull);
  });
}
