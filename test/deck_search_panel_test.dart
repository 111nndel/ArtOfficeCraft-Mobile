import 'package:artofficecraft_mobile/native/deck_search_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Slide search can include notes and follows edits', (
    tester,
  ) async {
    final jumps = <int>[];
    final results = find.byWidgetPredicate(
      (widget) => widget is ListTile && widget.key is ValueKey<(String, int)>,
    );
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
    expect(results, findsOneWidget);
    await tester.tap(results);
    expect(jumps, [1]);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(results, findsNWidgets(2));
    expect(find.text('Заметки'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(('slide-match', 0))));
    expect(jumps, [1, 0]);

    await show([
      {'title': 'Изменённый слайд'},
    ]);
    expect(find.text('Совпадений нет'), findsOneWidget);
    expect(results, findsNothing);
  });
}
