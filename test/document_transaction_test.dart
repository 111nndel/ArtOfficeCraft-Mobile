import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:flutter_test/flutter_test.dart';

class BrokenPreview implements DocumentBackend {
  bool broken = true;
  @override
  Future<Uint8List> create([String text = '']) async => Uint8List.fromList([1]);
  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async =>
      Uint8List.fromList([2]);
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async {
    if (broken) throw const FormatException('cannot display edited file');
    return {
      'value': bytes.single,
      'nested': [
        <String, dynamic>{'test': true},
      ],
    };
  }
}

void main() {
  test('No replacement snapshot is published when inspection fails; retry is immutable', () async {
    final backend = BrokenPreview(), before = Uint8List.fromList([1]);
    await expectLater(
      backend.editAndInspect(before, {}),
      throwsFormatException,
    );
    expect(before.single, 1);
    backend.broken = false;
    final result = await backend.editAndInspect(before, {});
    expect(result.bytes.single, 2);
    expect(result.preview['value'], 2);
    expect(() => result.bytes[0] = 99, throwsUnsupportedError);
    expect(
      () => (result.preview['nested'][0] as Map)['test'] = false,
      throwsUnsupportedError,
    );
  });
  test(
    'Malformed/cyclic requests fail before starting a native worker',
    () async {
      final backend = NativeDocumentBackend(
        NativeDocumentKind.word,
        libraryPath: 'unavailable',
      );
      final cycle = <String, dynamic>{};
      cycle['self'] = cycle;
      for (final payload in [
        <String, dynamic>{'object': Object()},
        cycle,
      ]) {
        await expectLater(
          backend.editInspected(Uint8List.fromList([1]), payload),
          throwsArgumentError,
        );
      }
      expect(backend.workerStarts, 0);
      await backend.close();
    },
  );
}
