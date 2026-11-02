import 'package:artofficecraft_mobile/native/deck_text_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'PPTX text can be applied after changing it without controller disposal errors',
    (tester) async {
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  saved = await showDeckTextDialog(
                    context,
                    'Изменить текст',
                    initial: 'Sprint presentation',
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Sprint presentation QA',
      );
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(saved, 'Sprint presentation QA');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancel returns null and does not keep a mounted text controller',
    (tester) async {
      String? saved = 'not canceled';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  saved = await showDeckTextDialog(
                    context,
                    'Новый текстовый блок',
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
