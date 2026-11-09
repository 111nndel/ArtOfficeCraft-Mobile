import 'package:artofficecraft_mobile/native/word_paragraph_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Formatting sheet keeps the inline UTF16 selection without a second text editor',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showWordParagraphEditor(
                    context,
                    formatOnly: true,
                    initialSelection: const TextSelection(
                      baseOffset: 3,
                      extentOffset: 5,
                    ),
                    block: {
                      'text': 'A😀BC',
                      'align': 'justify',
                      'runs': [
                        {'text': 'A😀', 'bold': true},
                        {'text': 'BC', 'italic': true},
                      ],
                    },
                  );
                },
                child: const Text('Оформление'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Оформление'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Форматирование выделенного текста'), findsOneWidget);
      final chips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .toList();
      expect(chips[0].selected, isFalse);
      expect(chips[1].selected, isTrue);
      await tester.tap(find.byType(DropdownButtonFormField<double>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('18').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Применить к документу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Применить к документу'));
      await tester.pumpAndSettle();
      expect(result?['text'], 'A😀BC');
      expect(result?['start'], 3);
      expect(result?['end'], 5);
      expect(result?['char'], {'size': 18.0});
      expect(tester.takeException(), isNull);
    },
  );
}
