import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show setup;
import 'office_features_backend.dart';
import 'office_features_test.dart' show tool, press, historyAction;

void main() {
  testWidgets(
    'Range commands preserve outside cells and styles, undo/redo and failed edits are atomic',
    (tester) async {
      final backend = FeaturesBackend({
        'sheets': [
          {
            'name': 'Data',
            'cells': {
              'A1': {
                'input': '12',
                'display': '12',
                'style': {'color': '#3565CA'},
              },
              'B1': {'input': '=A1*2', 'display': '24'},
              'D1': {'input': 'outside', 'display': 'outside'},
            },
          },
        ],
      });
      await setup(
        tester,
        const Size(320, 800),
        1.6,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: await backend.create()),
        ),
      );
      await tool(tester, 'Данные', 'Выделить диапазон');
      await tester.enterText(
        find.byKey(const Key('grid-range-input')),
        'B2:A1',
      );
      await press(tester, 'Выделить ячейки');
      tester
          .state<EditorToolPanelState>(find.byType(EditorToolPanel))
          .openTool(0, []);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Жирный'));
      await tester.pumpAndSettle();
      expect(backend.requests.last['range'], 'A1:B2');
      Map cells() => backend.viewed!['sheets'][0]['cells'] as Map;
      expect(cells()['B2']['style']['bold'], true);
      expect(cells()['A1']['style']['color'], '#3565CA');
      expect(cells()['B1']['input'], '=A1*2');
      backend.failEdit = true;
      tester
          .state<EditorToolPanelState>(find.byType(EditorToolPanel))
          .openTool(0, []);
      await tester.pumpAndSettle();
      await press(tester, 'Очистить содержимое');
      expect(cells()['B1']['input'], '=A1*2');
      backend.failEdit = false;
      tester
          .state<EditorToolPanelState>(find.byType(EditorToolPanel))
          .openTool(0, []);
      await tester.pumpAndSettle();
      await press(tester, 'Очистить содержимое');
      expect(cells()['A1']['input'], '');
      expect(cells()['B1']['input'], '');
      expect(cells()['A1']['style']['color'], '#3565CA');
      expect(cells()['B2']['style']['bold'], true);
      expect(cells()['D1']['input'], 'outside');
      await historyAction(tester, true);
      expect(cells()['B1']['input'], '=A1*2');
      await historyAction(tester, false);
      expect(cells()['B1']['input'], '');
      await tool(tester, 'Данные', 'Выделить диапазон');
      await tester.enterText(
        find.byKey(const Key('grid-range-input')),
        'A1:XFD1048576',
      );
      await press(tester, 'Выделить ячейки');
      expect(find.textContaining('Выберите не более'), findsOneWidget);
      expect(
        tester.widget<EditorToolPanel>(find.byType(EditorToolPanel)).undo,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
