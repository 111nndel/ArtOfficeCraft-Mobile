import 'dart:io';

import 'package:artofficecraft_mobile/native/deckcraft_bridge.dart';

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Need path to artoffice_core.dll');
  final deck = DeckCraftBridge.openLibraryForTesting(args.first);
  final first = deck.create();
  if (first.length < 200 || first[0] != 0x50 || first[1] != 0x4b) {
    throw StateError('Not PPTX data');
  }
  final step1 = deck.edit(first, {
    'action': 'add_slide',
    'text': 'Sprint presentation',
  });
  final step2 = deck.edit(step1, {
    'action': 'add_text',
    'slide': 1,
    'text': 'Second text block',
  });
  final preview = deck.inspect(step2);
  final slides = (preview['slides'] as List).cast<Map<String, dynamic>>();
  if (slides.length != 2) throw StateError('Slide not added');
  final shapes = (slides[1]['shapes'] as List).cast<Map<String, dynamic>>();
  final shape = shapes.firstWhere((s) => s['text'] == 'Second text block');
  final result = deck.edit(step2, {
    'action': 'edit_text',
    'slide': 1,
    'shape': shape['id'],
    'text': 'Edited text on slide',
  });
  final checked = deck.inspect(result);
  final found = ((checked['slides'] as List)[1]['shapes'] as List).any(
    (s) => s['text'] == 'Edited text on slide',
  );
  if (!found) throw StateError('PPTX text edit not retained');
  final dir = Directory('tools/emulator-fixtures');
  dir.createSync(recursive: true);
  final file = File('tools/emulator-fixtures/aoc-test.pptx');
  file.writeAsBytesSync(result);
  stdout.writeln(
    'PASS DeckCraft Dart FFI: create, add slide, add text, change text, reopen',
  );
  stdout.writeln('PPTX bytes ${result.length}; saved ${file.path}');
}
