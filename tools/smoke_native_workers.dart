import 'dart:convert';
import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_build_info.dart';
import 'package:artofficecraft_mobile/native/native_pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/native/grid_clipboard.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/platform/system_clipboard.dart';

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
            final clipboard = GridClipboard(_HostClipboard());
            final copied = await backend.copyGrid(edited.bytes, {
              'sheet': 0, 'range': 'B2',
            });
            await clipboard.write(GridClip(edited.bytes, 0, copied));
            final rich = (await clipboard.read())?.rich;
            check(rich != null, 'Portable rich clipboard unavailable');
            final pasted = await backend.pasteGrid(
              created, rich!.source,
              {'sheet': 0, 'address': 'C3', 'sourceSheet': rich.sheet,
                'sourceRange': rich.range.address, 'mode': 'all'},
              GridWindow(0, 0, 0), 'C3',
            );
            final reopened = await backend.inspect(pasted.bytes);
            final pastedCells = (reopened['sheets'] as List).first['cells'] as Map;
            check(pastedCells['C3']['input'] == '=SUM(12,8)' &&
              pastedCells['C3']['display'] == '20', 'Clipboard formula lost');
            clipboard.clearLocal();
            stdout.writeln('PASS grid clipboard: portable session, native copy/paste, reopen');
          case NativeDocumentKind.deck:
            check(jsonEncode(preview).contains('Linux edit 😀'), 'Deck edit lost');
          case NativeDocumentKind.pdf:
            check((preview['pages'] as List).length == 2, 'PDF edit lost');
            final renderer = NativePdfPageRenderer();
            final session = await renderer.open(edited.bytes);
            try {
              final png = await renderer.render(session, 1, width: 600);
              check(png.take(8).join(',') == '137,80,78,71,13,10,26,10' &&
                renderer.nativeRenders == 1 && renderer.fallbackRenders == 0,
                'Portable PDF worker raster failed');
            } finally { await renderer.close(session); }
            stdout.writeln('PASS PDF raster: portable worker, real FFI, no OS fallback');
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

class _HostClipboard implements SystemClipboard {
  @override
  bool get supportsIdentity => true;
  SystemClipboardContents? value;
  @override
  Future<void> write(SystemClipboardContents contents) async { value = contents; }
  @override
  Future<SystemClipboardContents?> read() async => value;
}
