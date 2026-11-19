import 'package:artofficecraft_mobile/native/deck_search_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Slide search finds literal text in shapes, skips notes and follows edits',
    (tester) async {
      final jumps = <int>[];
      Future<void> show(List<Map<String, dynamic>> slides) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeckSearchPanel(slides: slides, onJump: jumps.add),
          ),
        ),
      );
      await show([
        {'title': 'Title', 'notes': 'цена [р.]'},
        {
          'shapes': [
            {'text': 'Цена [р.]'},
            {'text': 'Цена [р.]'},
          ],
        },
      ]);
      await tester.enterText(find.byKey(const Key('deck-search')), '[Р.]');
      await tester.pump();
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      expect(jumps, [1]);
      await show([
        {'title': 'Изменённый слайд'},
      ]);
      expect(find.text('Совпадений нет'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    },
  );
}
