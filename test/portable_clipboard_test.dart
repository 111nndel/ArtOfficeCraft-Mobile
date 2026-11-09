import 'dart:async';

import 'package:artofficecraft_mobile/native/grid_clipboard.dart';
import 'package:artofficecraft_mobile/platform/flutter_text_clipboard.dart';
import 'package:artofficecraft_mobile/platform/system_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySystemClipboard implements SystemClipboard {
  @override
  bool get supportsIdentity => true;
  SystemClipboardContents? value;
  final firstStarted = Completer<void>();
  final firstWrite = Completer<void>();
  final operations = <String>[];
  bool holdFirstWrite = true;

  @override
  Future<void> write(SystemClipboardContents contents) async {
    operations.add('write:${contents.text}');
    if (!firstStarted.isCompleted) {
      firstStarted.complete();
      if (holdFirstWrite) await firstWrite.future;
    }
    value = contents;
  }

  @override
  Future<SystemClipboardContents?> read() async {
    operations.add('read');
    return value;
  }
}

GridClip clip(String text) => GridClip(Uint8List.fromList([1, 2, 3]), 0, {
  'range': 'A1', 'rows': 1, 'columns': 1, 'text': text,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Queued copies finish in order and a read sees the final range', () async {
    final port = MemorySystemClipboard();
    final clipboard = GridClipboard(port);
    final first = clipboard.write(clip('first'));
    await port.firstStarted.future;
    final last = clip('last');
    final second = clipboard.write(last);
    final read = clipboard.read();
    expect(port.operations, ['write:first']);
    expect(clipboard.current, isNull);
    port.firstWrite.complete();
    await Future.wait([first, second]);
    expect((await read)!.rich, same(last));
    expect(port.operations, ['write:first', 'write:last', 'read']);
  });

  test('Clearing a pending copy never resurrects its workbook snapshot', () async {
    final port = MemorySystemClipboard();
    final clipboard = GridClipboard(port);
    final copy = clipboard.write(clip('old'));
    await port.firstStarted.future;
    clipboard.clearLocal();
    port.firstWrite.complete();
    await copy;
    expect(clipboard.current, isNull);
    expect((await clipboard.read())!.rich, isNull);
    final next = clip('new');
    await clipboard.write(next);
    expect((await clipboard.read())!.rich, same(next));
  });

  test('External equal text clears rich data even on a capable adapter', () async {
    final port = MemorySystemClipboard()..holdFirstWrite = false;
    final clipboard = GridClipboard(port);
    final entry = clip('same text');
    await clipboard.write(entry);
    port.value = (text: entry.text, token: null);
    expect((await clipboard.read())!.rich, isNull);
    expect(clipboard.current, isNull);
  });

  test('Portable Flutter clipboard exposes text without retaining rich bytes', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? text;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        text = (call.arguments as Map)['text'] as String;
        return null;
      }
      if (call.method == 'Clipboard.getData') return {'text': text};
      throw StateError('Unexpected clipboard method: ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final clipboard = GridClipboard(const FlutterTextClipboard());
    await clipboard.write(clip('10\t20'));
    expect(text, '10\t20');
    expect(clipboard.supportsFormatting, isFalse);
    expect(clipboard.current, isNull);
    expect(await clipboard.read(), (text: '10\t20', rich: null));
    text = ''; // An empty external clipboard still behaves as cancellation.
    expect(await clipboard.read(), isNull);
  });
}
