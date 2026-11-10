import 'package:artofficecraft_mobile/native/word_document_index.dart';
import 'package:artofficecraft_mobile/native/word_navigation_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Heading navigation stays lazy, filters titles and validates paragraph numbers',
    (tester) async {
      tester.view.physicalSize = const Size(393, 873);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final jumps = <int>[];
      final index = WordDocumentIndex(
        List.generate(
          2000,
          (i) => {
            'block': i * 2,
            'text': 'Раздел $i — ${'длинный заголовок ' * 6}',
            'outlineLevel': i % 9,
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WordNavigationPanel(
                index: index,
                enabled: true,
                onJump: jumps.add,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ListTile).evaluate().length, lessThan(20));
      await tester.enterText(find.byKey(const Key('word-jump-number')), '0');
      await tester.tap(find.byTooltip('Перейти к абзацу'));
      await tester.pump();
      expect(jumps, isEmpty);
      expect(find.text('Введите номер от 1 до 2000'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('word-jump-number')), '2000');
      await tester.tap(find.byTooltip('Перейти к абзацу'));
      expect(jumps, [1999]);
      await tester.enterText(
        find.byKey(const Key('word-heading-filter')),
        'РАЗДЕЛ 1999',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey(('word-heading', 1999))),
      );
      await tester.tap(find.byKey(const ValueKey(('word-heading', 1999))));
      expect(jumps, [1999, 1999]);
      expect(tester.takeException(), isNull);
    },
  );
}
