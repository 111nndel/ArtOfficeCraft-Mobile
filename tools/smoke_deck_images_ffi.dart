import 'dart:io';

import 'package:artofficecraft_mobile/native/deckcraft_bridge.dart';

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('DLL path and test PPTX path required');
  }
  final bridge = DeckCraftBridge.openLibraryForTesting(args[0]);
  final doc = File(args[1]).readAsBytesSync();
  final inspected = bridge.inspect(doc);
  final slides = inspected['slides'] as List;
  if (slides.length < 2) throw StateError('Expected two test slides');
  final shape = (slides[1]['shapes'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((s) => s['imageId'] is int);
  final id = shape['imageId'] as int;
  final picture = bridge.image(doc, 1, id);
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (picture.length < 100 ||
      !signature.asMap().entries.every((e) => picture[e.key] == e.value)) {
    throw StateError('Native PPTX picture is not PNG');
  }
  try {
    bridge.image(doc, 0, id);
    throw StateError('Unreferenced slide image wrongly exposed');
  } on FormatException {
    // A slide cannot request media from another slide.
  }
  final next = bridge.edit(doc, <String, dynamic>{
    'action': 'add_text',
    'slide': 1,
    'text': 'Picture roundtrip',
  });
  final report = bridge.inspect(next);
  final after = (report['slides'] as List)[1]['shapes'] as List;
  stdout.writeln(
    'MEDIA BEFORE ${(slides[1]['shapes'] as List).map((s) => s['imageId']).toList()}',
  );
  stdout.writeln('MEDIA AFTER ${after.map((s) => s['imageId']).toList()}');
  final newId = after.map((s) => s['imageId']).whereType<int>().single;
  final afterPicture = bridge.image(next, 1, newId);
  if (afterPicture.length != picture.length ||
      !afterPicture.asMap().entries.every((e) => picture[e.key] == e.value)) {
    throw StateError('Export damaged the embedded picture');
  }
  stdout.writeln(
    'PASS_DECK_IMAGE_FFI id=$id pngBytes=${picture.length} postEditBytes=${afterPicture.length}',
  );
}
