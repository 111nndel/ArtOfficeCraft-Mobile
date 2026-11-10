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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
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
      await tester.ensureVisible(find.byTooltip('Перейти к абзацу'));
      await tester.tap(find.byTooltip('Перейти к абзацу'));
      await tester.pump();
      expect(jumps, isEmpty);
      expect(find.text('Введите номер от 1 до 2000'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('word-jump-number')), '2000');
      await tester.ensureVisible(find.byTooltip('Перейти к абзацу'));
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
      expect(
        tester.getSize(find.byKey(const Key('word-heading-list'))).height,
        lessThan(140),
      );
      await tester.ensureVisible(find.byTooltip('Очистить поиск'));
      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('word-heading-filter')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byType(ListTile).evaluate().length, lessThan(20));

      expect(tester.takeException(), isNull);
    },
  );
}
