import 'dart:io';

import 'package:artofficecraft_mobile/native/pdfcraft_bridge.dart';

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Path to artoffice_core.dll required');
  }
  final pdf = PdfCraftBridge.openLibraryForTesting(args.first);
  final first = pdf.create();
  if (first.length < 100 || String.fromCharCodes(first.take(5)) != '%PDF-') {
    throw StateError('Not a valid PDF header');
  }
  final second = pdf.edit(first, {'action': 'duplicate', 'page': 0});
  final third = pdf.edit(second, {'action': 'rotate_cw', 'page': 0});
  final preview = pdf.inspect(third);
  if (preview['pageCount'] != 2) throw StateError('Page duplication failed');
  final pages = preview['pages'] as List;
  if (pages[0]['rotation'] != 90) throw StateError('Page rotation failed');
  final dir = Directory('tools/emulator-fixtures');
  dir.createSync(recursive: true);
  final file = File('tools/emulator-fixtures/aoc-test.pdf');
  file.writeAsBytesSync(third);
  final reopened = pdf.inspect(file.readAsBytesSync());
  if (reopened['pageCount'] != 2) throw StateError('Saved PDF cannot be read');
  stdout.writeln(
    'PASS PDFCraft Dart FFI: create, duplicate, rotate, save and reopen',
  );
  stdout.writeln('PDF bytes: ${third.length}');
}
