import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_merge_test.dart' show MergeBackend, open, select, formula;
import 'office_features_test.dart' show tool, press;

void main() {
  testWidgets(
    'Rejected fill keeps pending input and can be retried without a separate commit',
    (tester) async {
      final backend = MergeBackend()..failEdit = true;
      await open(tester, backend);
      await select(tester, 'A1:A3');
      await tester.enterText(formula, 'retry draft');
      await tool(tester, 'Главная', 'Заполнить диапазон');
      await press(tester, 'Заполнить вниз');
      expect(tester.widget<TextField>(formula).controller!.text, 'retry draft');
      expect(backend.requests.single, containsPair('action', 'fill_range'));
      expect(backend.requests.single, containsPair('value', 'retry draft'));
      expect(backend.requests.single, containsPair('range', 'A1:A3'));
      await press(tester, 'Заполнить вниз');
      expect(backend.requests, hasLength(2));
      expect(backend.requests.every((r) => r['action'] == 'fill_range'), true);
      expect(tester.widget<TextField>(formula).controller!.text, 'retry draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Fill explains unavailable ranges and offers translated controls',
    (tester) async {
      final backend = MergeBackend(table: true);
      await open(tester, backend, english: true);
      await select(tester, 'A1:B2', english: true);
      await tool(tester, 'Главная', 'Заполнить диапазон');
      expect(find.text('Fill down'), findsOneWidget);
      expect(find.text('Fill right'), findsOneWidget);
      expect(
        find.text(
          'For filling, select a range without merged cells or Excel tables',
        ),
        findsOneWidget,
      );
      final buttons = tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      );
      expect(buttons, isNotEmpty);
      expect(buttons.every((b) => b.onPressed == null), true);
      final panel = tester.widget<EditorToolPanel>(
        find.byType(EditorToolPanel),
      );
      expect(panel.undo, isNull);
      expect(backend.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
