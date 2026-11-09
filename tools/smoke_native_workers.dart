import 'dart:convert';
import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_build_info.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Compile beside lib/libartoffice_core.so on Linux. No explicit library path
/// and no Flutter runner: exercises the same loader/isolates used by the app.
Future<void> main() async {
  final info = await readNativeBuildInfo();
  check(info?['abi'] == 1, 'Native build info/ABI unavailable');
  final directory = await Directory.systemTemp.createTemp('aoc-native-worker-');
  try {
    for (final kind in NativeDocumentKind.values) {
      final backend = NativeDocumentBackend.tryOpen(kind);
      if (backend == null) throw StateError('Cannot open ${kind.name}');
      try {
        final created = await backend.create('Portable document');
        final request = switch (kind) {
          NativeDocumentKind.word => <String, dynamic>{
            'action': 'paragraph', 'block': 0, 'text': 'Linux edit 😀',
          },
          NativeDocumentKind.grid => <String, dynamic>{
            'sheet': 0, 'address': 'B2', 'value': '=SUM(12,8)',
          },
          NativeDocumentKind.deck => <String, dynamic>{
            'action': 'add_text', 'slide': 0, 'text': 'Linux edit 😀',
          },
          NativeDocumentKind.pdf => <String, dynamic>{
            'action': 'duplicate', 'page': 0,
          },
        };
        final edited = await backend.editAndInspect(created, request);
        final file = File('${directory.path}/${kind.name}.bin');
        await file.writeAsBytes(edited.bytes, flush: true);
        final preview = await backend.inspect(await file.readAsBytes());
        switch (kind) {
          case NativeDocumentKind.word:
            check((preview['paragraphs'] as List).contains('Linux edit 😀'),
              'Word edit lost');
          case NativeDocumentKind.grid:
            final cells = (preview['sheets'] as List).first['cells'] as Map;
            check(cells['B2']['display'] == '20', 'Grid formula lost');
          case NativeDocumentKind.deck:
            check(jsonEncode(preview).contains('Linux edit 😀'), 'Deck edit lost');
          case NativeDocumentKind.pdf:
            check((preview['pages'] as List).length == 2, 'PDF edit lost');
        }
        stdout.writeln('PASS ${kind.name}: default loader, worker, edit, reopen');
      } finally {
        await closeDocumentBackend(backend);
      }
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
