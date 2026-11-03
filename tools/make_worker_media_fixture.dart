import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';

/// Generate an original two-slide base using the pinned native DeckCraft adapter.
/// Then run make_pptx_image_fixture.py to add the original PNG pattern.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the Windows native DLL path');
  final backend = NativeDocumentBackend(
    NativeDocumentKind.deck,
    libraryPath: args.single,
  );
  try {
    final first = await backend.create();
    final second = await backend.edit(first, {
      'action': 'add_slide',
      'text': 'Worker media fixture',
    });
    await Directory('build/worker-fixture').create(recursive: true);
    await File('build/worker-fixture/base.pptx').writeAsBytes(second);
  } finally {
    await backend.close();
  }
}
