import 'dart:convert';
import 'dart:io';
import 'package:artofficecraft_mobile/native/wordcraft_bridge.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tools/smoke_word_ffi.dart <path to DLL>');
    exit(2);
  }
  final bridge = WordCraftBridge.openLibraryForTesting(args.first);
  final first = 'Первый абзац на русском';
  final created = bridge.create(first);
  if (created.length < 100 || created[0] != 0x50 || created[1] != 0x4b) {
    throw StateError('Rust did not generate DOCX ZIP data');
  }
  final opened = bridge.inspect(created);
  if (!(opened['paragraphs'] as List).contains(first)) {
    throw StateError('Cannot inspect created DOCX');
  }
  final updated = bridge.appendParagraph(created, 'Второй абзац');
  final result = bridge.inspect(updated);
  if (!(result['paragraphs'] as List).contains('Второй абзац')) {
    throw StateError('Appended paragraph not persisted');
  }
  stdout.writeln(jsonEncode({
    'result': 'PASS',
    'createBytes': created.length,
    'updatedBytes': updated.length,
    'paragraphs': (result['paragraphs'] as List).length,
  }));
}
