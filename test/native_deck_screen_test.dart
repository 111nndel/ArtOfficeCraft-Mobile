import 'dart:convert';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';

class PictureDeck implements DocumentBackend, DocumentImages {
  final requests = <int, int>{};
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<Uint8List> create([String text = '']) async => Uint8List(1);

  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async => {
    'slides': [
      {
        'shapes': [
          for (var i = 0; i < 15; i++)
            {
              'id': i + 1,
              'imageId': i + 100,
              'rect': {
                'x': (i % 5) * 160,
                'y': (i ~/ 5) * 160,
                'w': 150,
                'h': 150,
              },
            },
        ],
      },
    ],
  };

  @override
  Future<Uint8List> image(Uint8List bytes, int slide, int media) async {
    requests.update(media, (count) => count + 1, ifAbsent: () => 1);
    return png;
  }

  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
    'PPTX displays more than twelve embedded pictures and reuses mounted futures',
    (tester) async {
      final deck = PictureDeck();
      final bytes = await deck.create();
      Widget app() => MaterialApp(
        home: NativeDeckScreen(
          backend: deck,
          launch: EditorLaunch(bytes: bytes),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        deck.requests.keys,
        containsAll(List.generate(15, (i) => i + 100)),
      );
      expect(find.byType(Image), findsAtLeastNWidgets(15));

      await tester.tap(find.byKey(const Key('deck-object-editing')));
      await tester.pumpAndSettle();
      final counts = Map.of(deck.requests);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(deck.requests, counts);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DeckCraft reports unavailable native operations', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NativeDeckScreen()));
    expect(find.textContaining('Rust недоступен'), findsWidgets);
    final menu = tester.widget<EditorFileMenu>(find.byType(EditorFileMenu));
    expect(
      menu.commands.firstWhere((c) => c.label == 'Открыть PPTX').onPressed,
      isNull,
    );
  });
}
