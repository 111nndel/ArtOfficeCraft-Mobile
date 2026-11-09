import 'dart:convert';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryWord implements DocumentBackend {
  bool failInspect = false;
  @override
  Future<Uint8List> create([String text = '']) async =>
      Uint8List.fromList(utf8.encode('Original'));
  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async =>
      Uint8List.fromList(utf8.encode(request['text'] as String));
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async {
    if (failInspect) {
      failInspect = false;
      throw const FormatException('restore failed');
    }
    final text = utf8.decode(bytes);
    return {
      'paragraphs': [text],
      'tables': 0,
      'blocks': [
        {
          'block': 0,
          'text': text,
          'editable': true,
          'align': 'left',
          'runs': [
            {'text': text},
          ],
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'Failed Word undo keeps the document and the undo target for retry',
    (tester) async {
      final backend = MemoryWord();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeWordScreen(
            backend: backend,
            launch: const EditorLaunch(create: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        'Changed',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Развернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Готово'));
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(find.text('Changed'), findsOneWidget);
      backend.failInspect = true;
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(find.text('Changed'), findsOneWidget);
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsOneWidget);
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Changed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
