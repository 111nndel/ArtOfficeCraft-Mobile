import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:artofficecraft_mobile/native/word_inline_controller.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> until(
    WidgetTester tester,
    bool Function() done,
    String label,
  ) async {
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (done()) return;
    }
    throw StateError('Timed out: $label');
  }

  EditorToolPanel panel(WidgetTester tester) =>
      tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
  Future<void> present(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(theme: OfficeTheme.build(Brightness.light), home: screen),
    );
    await until(
      tester,
      () => find.byType(EditorToolPanel).evaluate().isNotEmpty,
      'native document loaded',
    );
    await tester.pumpAndSettle();
  }

  Future<void> tool(
    WidgetTester tester,
    String section,
    String name, {
    int? child,
  }) async {
    final p = panel(tester),
        state = tester.state<EditorToolPanelState>(
          find.byType(EditorToolPanel),
        );
    final i = p.sections.indexWhere((s) => s.label == section);
    final j = p.sections[i].tools.indexWhere((t) => t.label == name);
    state.openTool(i, [j, ?child]);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pump();
  }

  Future<void> collapse(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final f = find.byTooltip('Свернуть инструменты');
    if (f.evaluate().isNotEmpty) await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> history(WidgetTester tester, bool undo) async {
    await collapse(tester);
    await tester.tap(find.byTooltip(undo ? 'Отменить' : 'Повторить'));
    await until(
      tester,
      () => (undo ? panel(tester).redo : panel(tester).undo) != null,
      'history restore',
    );
    await tester.pumpAndSettle();
  }

  Future<Uint8List> save(WidgetTester tester, String label) async {
    Uint8List? output;
    const channel = MethodChannel('flutter_file_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          output = Uint8List.fromList(
            (call.arguments as Map)['data'] as Uint8List,
          );
          return '/test/Office-feature-copy';
        });
    try {
      await collapse(tester);
      await tester.tap(find.byTooltip('Меню файла'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await until(tester, () => output != null, 'exported document');
      await tester.pumpAndSettle();
      return output!;
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    final bytes = await binding.takeScreenshot(name);
    final path = '${Directory.systemTemp.path}/aoc-$name.png';
    await File(path).writeAsBytes(bytes, flush: true);
    debugPrint('DESIGN_SCREENSHOT $path');
  }

  String cellInput(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('formula-input')),
          matching: find.byType(TextField),
        ),
      )
      .controller!
      .text;

  Future<void> selectRange(
    WidgetTester tester,
    String range,
    String expectedInput,
  ) async {
    await tool(tester, 'Данные', 'Выделить диапазон');
    final field = find.byKey(const Key('grid-range-input'));
    await tester.enterText(field, range);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, range);
    await press(tester, 'Выделить ячейки');
    await until(
      tester,
      () => cellInput(tester) == expectedInput,
      'range $range applied',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      false,
    );
  }

  Future<void> selectVisibleCell(
    WidgetTester tester,
    String address,
    String expectedInput,
  ) async {
    await collapse(tester);
    final cell = find.byKey(ValueKey('grid-cell-$address')).hitTestable();
    await until(tester, () => cell.evaluate().isNotEmpty, 'visible $address');
    await tester.tap(cell);
    await until(
      tester,
      () => cellInput(tester) == expectedInput,
      'selected $address',
    );
  }

  Future<Map<String, dynamic>> inspectCell(
    NativeDocumentBackend backend,
    Uint8List bytes,
    String address, {
    int sheet = 0,
  }) async =>
      (await backend.inspectGrid(
            bytes,
            GridWindow(sheet, 0, 0),
            address,
          ))['selection']
          as Map<String, dynamic>;

  testWidgets(
    'Excel finds distant cells and formulas across sheets without losing pending input',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var original = await backend.create();
      for (final entry in {
        'A1': 'Чай',
        'D4': 'Чай с молоком',
        'AY6001': 'ЧАЙ',
        'C6': '=SUM(B1:B2)',
      }.entries) {
        original = await backend.edit(original, {
          'sheet': 0, 'address': entry.key, 'value': entry.value,
        });
      }
      final firstName = ((await backend.inspect(original))['sheets'] as List)
          .first['name'] as String;
      original = await backend.edit(original, {
        'action': 'add_sheet', 'sheet': 0, 'address': 'A1', 'name': 'Другой лист',
      });
      original = await backend.edit(original, {
        'sheet': 1, 'address': 'B2', 'value': 'Чай',
      });
      await present(tester, NativeGridScreen(
        backend: backend,
        launch: EditorLaunch(bytes: original, name: 'Find.xlsx'),
      ));
      await tool(tester, 'Вид', 'Управление листами');
      await press(tester, firstName);
      await collapse(tester);
      final input = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'Новый чай');
      await tool(tester, 'Главная', 'Найти');
      final query = find.byKey(const Key('grid-find-input'));
      await tester.enterText(query, 'ЧаЙ');
      await tester.pumpAndSettle();
      await press(tester, 'Найти в Excel');
      await until(tester, () => find.text('Результат 1 из 3').evaluate().isNotEmpty,
          'first Excel match');
      expect(cellInput(tester), 'Новый чай');

      await tester.tap(find.byTooltip('Следующее совпадение'));
      await until(tester, () => cellInput(tester) == 'Чай с молоком', 'second match');
      await tester.tap(find.byTooltip('Следующее совпадение'));
      await until(tester, () => cellInput(tester) == 'ЧАЙ', 'far match');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('grid-cell-AY6001')).hitTestable(),
          findsOneWidget);
      await capture(tester, 'grid-find-038');

      await tester.enterText(input, 'Изменено');
      await tester.tap(find.byTooltip('Следующее совпадение'));
      await until(tester, () => cellInput(tester) == 'Новый чай',
          'requery after pending input');
      expect(find.text('Результат 1 из 2'), findsOneWidget);
      final saved = await save(tester, 'Сохранить копию');
      expect((await inspectCell(backend, saved, 'AY6001'))['input'], 'Изменено');
      expect((await inspectCell(backend, saved, 'A1'))['input'], 'Новый чай');

      await tool(tester, 'Главная', 'Найти');
      await tester.ensureVisible(find.byKey(const Key('grid-find-workbook')));
      await tester.tap(find.byKey(const Key('grid-find-workbook')));
      await tester.pumpAndSettle();
      await press(tester, 'Найти в Excel');
      await until(tester, () => find.text('Результат 1 из 3').evaluate().isNotEmpty,
          'whole workbook search');
      await tester.tap(find.byTooltip('Предыдущее совпадение'));
      await until(tester, () => cellInput(tester) == 'Чай', 'other sheet match');
      expect(find.text('Другой лист · B2'), findsOneWidget);

      await tool(tester, 'Главная', 'Найти');
      await tester.enterText(query, 'SUM');
      await tester.pumpAndSettle();
      await press(tester, 'Найти в Excel');
      await until(tester, () => find.text('Совпадений не найдено').evaluate().isNotEmpty,
          'formulas excluded from value search');
      await tester.ensureVisible(find.byKey(const Key('grid-find-look-in')));
      await tester.tap(find.byKey(const Key('grid-find-look-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Формулы').last);
      await tester.pumpAndSettle();
      await press(tester, 'Найти в Excel');
      await until(tester, () => cellInput(tester) == '=SUM(B1:B2)', 'formula match');
      expect(find.text('Результат 1 из 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть поиск'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('grid-find-count')), findsNothing);

      await history(tester, true);
      final undo = await save(tester, 'Сохранить копию');
      expect((await inspectCell(backend, undo, 'AY6001'))['input'], 'ЧАЙ');
      expect((await inspectCell(backend, undo, 'A1'))['input'], 'Новый чай');
    },
  );

  testWidgets(
    'Filter a worksheet by value and blanks, undo, export and remove after reopening',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var original = await backend.create();
      for (final entry in {
        'A1': 'Drink',
        'B1': 'Stock',
        'A2': 'Tea',
        'B2': '15',
        'A3': 'Coffee',
        'B3': '25',
        'B4': '5',
        'A5': 'Tea',
        'B5': '12',
      }.entries) {
        original = await backend.edit(original, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      Future<void> open(Uint8List bytes) => present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: bytes, name: 'Stock.xlsx'),
        ),
      );
      Future<Map<String, dynamic>> inspect(Uint8List bytes) =>
          backend.inspectGrid(bytes, const GridWindow(0, 0, 0), 'A1');
      Finder choice(String? value) =>
          find.byKey(ValueKey(('filter-value', value)));

      await open(original);
      await selectRange(tester, 'A1:B5', 'Drink');
      await tool(tester, 'Данные', 'Фильтр');
      await until(
        tester,
        () => choice('Tea').evaluate().isNotEmpty,
        'filter values loaded',
      );
      await press(tester, 'Выбрать все значения');
      await press(tester, 'Tea');
      await press(tester, '(Пустые ячейки)');
      await tester.ensureVisible(find.text('Применить фильтр'));
      await tester.pumpAndSettle();
      await capture(tester, 'grid-filter-028');
      await press(tester, 'Применить фильтр');
      await until(tester, () => panel(tester).undo != null, 'filter applied');
      final filtered = await save(tester, 'Сохранить копию');
      final view = await inspect(filtered);
      expect(view['filterRange'], 'A1:B5');
      final rows = GridLayout.fromJson(view['layout'] as Map).rows;
      expect(rows.extent(0), greaterThan(0));
      expect(rows.extent(2), 0);
      expect(rows.extent(3), greaterThan(0));
      expect((await inspectCell(backend, filtered, 'A3'))['input'], 'Coffee');

      await history(tester, true);
      await selectVisibleCell(tester, 'A3', 'Coffee');
      await history(tester, false);
      await until(
        tester,
        () => find.byKey(const ValueKey('grid-cell-A3')).evaluate().isEmpty,
        'filtered row hidden again',
      );

      await open(filtered);
      await tool(tester, 'Данные', 'Фильтр');
      await until(
        tester,
        () => choice('Coffee').evaluate().isNotEmpty,
        'saved filter values loaded',
      );
      expect(tester.widget<CheckboxListTile>(choice('Coffee')).value, false);
      expect(tester.widget<CheckboxListTile>(choice(null)).value, true);
      await press(tester, 'Снять автофильтр');
      await until(tester, () => panel(tester).undo != null, 'filter removed');
      final cleared = await save(tester, 'Сохранить копию');
      final clearedView = await inspect(cleared);
      expect(clearedView['filterRange'], isNull);
      expect(
        GridLayout.fromJson(clearedView['layout'] as Map).rows.extent(2),
        greaterThan(0),
      );
    },
  );

  testWidgets(
    'Sort selected rows by a chosen column and preserve the header, formulas and undo',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var original = await backend.create();
      for (final entry in {
        'A1': 'Product',
        'B1': 'Price',
        'A2': 'Tea',
        'B2': '10',
        'C2': '=B2*2',
        'A3': 'Coffee',
        'B3': '30',
        'C3': '=B3*2',
        'A4': 'Juice',
        'B4': '20',
        'C4': '=B4*2',
        'D2': 'Keep',
      }.entries) {
        original = await backend.edit(original, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Prices.xlsx'),
        ),
      );
      await selectRange(tester, 'A1:C4', 'Product');
      await tool(tester, 'Данные', 'Сортировать');
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdowns.first);
      await tester.tap(dropdowns.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('B').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(dropdowns.last);
      await tester.tap(dropdowns.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('По убыванию').last);
      await tester.pumpAndSettle();
      await press(tester, 'Первая строка — заголовок');
      await tester.pumpAndSettle();
      await capture(tester, 'grid-sort-027');
      await press(tester, 'Сортировать диапазон');
      await until(tester, () => panel(tester).undo != null, 'range sort');
      final sorted = await save(tester, 'Сохранить копию');
      expect((await inspectCell(backend, sorted, 'A1'))['input'], 'Product');
      expect((await inspectCell(backend, sorted, 'A2'))['input'], 'Coffee');
      expect((await inspectCell(backend, sorted, 'A3'))['input'], 'Juice');
      expect((await inspectCell(backend, sorted, 'C2'))['input'], '=B2*2');
      expect((await inspectCell(backend, sorted, 'C2'))['display'], '60');
      expect((await inspectCell(backend, sorted, 'D2'))['input'], 'Keep');
      await history(tester, true);
      await selectVisibleCell(tester, 'A2', 'Tea');
      await history(tester, false);
      await selectVisibleCell(tester, 'A2', 'Coffee');
    },
  );

  testWidgets(
    'Insert and delete whole rows from the tool panel with cross-sheet references and undo',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var original = await backend.create();
      for (final entry in {
        'A1': '10',
        'A2': '20',
        'A3': '30',
        'F1': '=SUM(A1:A3)',
        'AA2': 'Outside the selection',
      }.entries) {
        original = await backend.edit(original, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      original = await backend.edit(original, {
        'action': 'add_sheet',
        'sheet': 0,
        'address': 'A1',
        'name': 'Summary',
      });
      original = await backend.edit(original, {
        'sheet': 1,
        'address': 'A1',
        'value': r'=Sheet1!$A$3*2',
      });
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Rows.xlsx'),
        ),
      );
      await press(tester, 'Sheet1');
      await until(
        tester,
        () => cellInput(tester) == '10',
        'selected source sheet',
      );
      await selectRange(tester, 'A2:B3', '20');
      await tool(tester, 'Главная', 'Строки и столбцы');
      expect(find.text('Строки 2–3'), findsOneWidget);
      await capture(tester, 'grid-lines-pane-025');
      await press(tester, 'Вставить строки выше');
      await until(tester, () => panel(tester).undo != null, 'insert rows');
      final inserted = await save(tester, 'Сохранить копию');
      expect((await inspectCell(backend, inserted, 'A2'))['input'], '');
      expect(
        (await inspectCell(backend, inserted, 'AA4'))['input'],
        'Outside the selection',
      );
      expect(
        (await inspectCell(backend, inserted, 'F1'))['input'],
        '=SUM(A1:A5)',
      );
      expect(
        (await inspectCell(backend, inserted, 'A1', sheet: 1))['input'],
        r'=Sheet1!$A$5*2',
      );
      await history(tester, true);
      final undone = await save(tester, 'Сохранить копию');
      expect(
        (await inspectCell(backend, undone, 'F1'))['input'],
        '=SUM(A1:A3)',
      );
      expect(
        (await inspectCell(backend, undone, 'AA2'))['input'],
        'Outside the selection',
      );
      await history(tester, false);
      await selectVisibleCell(tester, 'A4', '20');
      await tool(tester, 'Главная', 'Строки и столбцы');
      await press(tester, 'Удалить строки');
      expect(find.text('Будут удалены строки 4 целиком.'), findsOneWidget);
      await press(tester, 'Удалить');
      await until(
        tester,
        () => cellInput(tester) == '30',
        'delete row and refresh active cell',
      );
      final deleted = await save(tester, 'Сохранить копию');
      expect((await inspectCell(backend, deleted, 'F1'))['display'], '40');
      expect((await inspectCell(backend, deleted, 'AA4'))['input'], '');
      expect(
        (await inspectCell(backend, deleted, 'A1', sheet: 1))['input'],
        r'=Sheet1!$A$4*2',
      );
      expect(
        (await inspectCell(backend, original, 'AA2'))['input'],
        'Outside the selection',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Insert columns and delete a referenced column while preserving styles and a valid XLSX',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var original = await backend.create();
      for (final entry in {'B1': '11', 'C1': '12', 'D1': '=B1+C1'}.entries) {
        original = await backend.edit(original, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      original = await backend.edit(original, {
        'sheet': 0,
        'address': 'D1',
        'action': 'format',
        'style': {'bold': true},
      });
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Columns.xlsx'),
        ),
      );
      await selectRange(tester, 'B1:C2', '11');
      await tool(tester, 'Главная', 'Строки и столбцы');
      expect(find.text('Столбцы B–C'), findsOneWidget);
      await press(tester, 'Вставить столбцы слева');
      await until(tester, () => panel(tester).undo != null, 'insert columns');
      final inserted = await save(tester, 'Сохранить копию');
      expect((await inspectCell(backend, inserted, 'F1'))['input'], '=D1+E1');
      expect((await inspectCell(backend, inserted, 'F1'))['display'], '23');
      expect(
        (await inspectCell(backend, inserted, 'F1'))['style']['bold'],
        true,
      );
      await selectVisibleCell(tester, 'D1', '11');
      await tool(tester, 'Главная', 'Строки и столбцы');
      await press(tester, 'Удалить столбцы');
      expect(find.text('Будут удалены столбцы D целиком.'), findsOneWidget);
      await capture(tester, 'grid-delete-column-025');
      await press(tester, 'Удалить');
      await until(tester, () => cellInput(tester) == '12', 'delete column');
      final deleted = await save(tester, 'Сохранить копию');
      final result = await inspectCell(backend, deleted, 'E1');
      expect(result['input'], '=#REF!+D1');
      expect(result['display'], '#REF!');
      expect(result['style']['bold'], true);
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: deleted, name: 'Reopened.xlsx'),
        ),
      );
      expect((await inspectCell(backend, deleted, 'D1'))['input'], '12');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Touch range formatting and clearing preserve styles and formulas through Rust export and undo',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var original = await backend.create();
      for (final entry in {
        'B2': '12',
        'C2': '=B2*2',
        'F1': '=SUM(B2:C2)',
      }.entries) {
        original = await backend.edit(original, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Ranges.xlsx'),
        ),
      );
      await tester.longPress(find.byKey(const ValueKey('grid-cell-B2')));
      await until(
        tester,
        () => find
            .byKey(const ValueKey('grid-selection-end'))
            .evaluate()
            .isNotEmpty,
        'touch selection',
      );
      final viewport = tester.state<SheetViewportState>(
        find.byType(SheetViewport),
      );
      final zoom = viewport.zoom;
      await tester.drag(
        find.byKey(const ValueKey('grid-selection-end')),
        Offset(
          viewport.columns.extent(1) * zoom,
          viewport.rows.extent(1) * zoom,
        ),
      );
      await tester.pumpAndSettle();
      await tool(tester, 'Данные', 'Выделить диапазон');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('grid-range-input')))
            .controller!
            .text,
        'B2:C3',
      );
      await tester.enterText(
        find.byKey(const Key('grid-range-input')),
        'B2:D4',
      );
      await press(tester, 'Выделить ячейки');
      await tester.pumpAndSettle();
      tester
          .state<EditorToolPanelState>(find.byType(EditorToolPanel))
          .openTool(0, []);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Жирный'));
      await until(tester, () => panel(tester).undo != null, 'range format');
      final formatted = await save(tester, 'Сохранить копию');
      var view = await backend.inspectGrid(
        formatted,
        const GridWindow(0, 0, 0),
        'B2',
      );
      expect(view['selection']['style']['bold'], true);
      view = await backend.inspectGrid(
        formatted,
        const GridWindow(0, 0, 0),
        'D4',
      );
      expect(view['selection']['style']['bold'], true);
      await capture(tester, 'grid-range-023');
      tester
          .state<EditorToolPanelState>(find.byType(EditorToolPanel))
          .openTool(0, []);
      await tester.pumpAndSettle();
      await press(tester, 'Очистить содержимое');
      await until(tester, () => panel(tester).undo != null, 'range clear');
      final cleared = await save(tester, 'Сохранить копию');
      view = await backend.inspectGrid(
        cleared,
        const GridWindow(0, 0, 0),
        'B2',
      );
      expect(view['selection']['input'], '');
      expect(view['selection']['style']['bold'], true);
      view = await backend.inspectGrid(
        cleared,
        const GridWindow(0, 0, 0),
        'F1',
      );
      expect(view['selection']['input'], '=SUM(B2:C2)');
      expect(view['selection']['display'], '0');
      await history(tester, true);
      final restored = await save(tester, 'Сохранить копию');
      view = await backend.inspectGrid(
        restored,
        const GridWindow(0, 0, 0),
        'C2',
      );
      expect(view['selection']['input'], '=B2*2');
      expect(view['selection']['style']['bold'], true);
      await history(tester, false);
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: cleared, name: 'Reopened.xlsx'),
        ),
      );
      expect(
        (await backend.inspectGrid(
          original,
          const GridWindow(0, 0, 0),
          'B2',
        ))['selection']['input'],
        '12',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Word Unicode selection color and paragraph geometry agree with saved and reopened DOCX',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.word);
      addTearDown(backend.close);
      const text = 'До 😀 после';
      final original = await backend.create(text);
      await present(
        tester,
        NativeWordScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Color.docx'),
        ),
      );
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
      Finder input() => find.byKey(const Key('word-inline-input'));
      TextField field() => tester.widget<TextField>(input());
      field().controller!.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 5,
      );
      await tester.pump();
      await tool(tester, 'Главная', 'Цвет текста');
      await press(tester, 'Синий');
      await until(tester, () => !field().readOnly, 'color');
      final span = (field().controller! as WordInlineController).buildTextSpan(
        context: tester.element(input()),
        withComposing: false,
      );
      expect(
        span.children!.cast<TextSpan>().any(
          (s) =>
              s.toPlainText() == '😀' &&
              s.style!.color == const Color(0xff3565ca),
        ),
        true,
      );
      await tool(tester, 'Макет', 'Отступы');
      await press(tester, '24 pt');
      await until(tester, () => !field().readOnly, 'indent');
      await tool(tester, 'Главная', 'Абзац', child: 4);
      await press(tester, '2.0');
      await until(tester, () => !field().readOnly, 'line spacing');
      expect(field().style!.height, 2.0);
      final saved = await save(tester, 'Сохранить как DOCX');
      final block = (await backend.inspect(saved))['blocks'][0] as Map;
      expect(block['indentLeft'], 24.0);
      expect(block['lineSpacing'], 2.0);
      expect(
        (block['runs'] as List).any(
          (r) => r['text'] == '😀' && r['color'] == '#3565CA',
        ),
        true,
      );
      await capture(tester, 'word-color-indent-023');
      await present(
        tester,
        NativeWordScreen(
          backend: backend,
          launch: EditorLaunch(bytes: saved, name: 'Reopened.docx'),
        ),
      );
      final rich = find.byWidgetPredicate(
        (w) => w is Text && w.textSpan?.toPlainText() == text,
      );
      expect(tester.widget<Text>(rich).style!.height, 2.0);
      final pads = tester.widgetList<Padding>(
        find.ancestor(of: rich, matching: find.byType(Padding)),
      );
      expect(
        pads.any(
          (p) =>
              p.padding is EdgeInsets && (p.padding as EdgeInsets).left == 32,
        ),
        true,
      );
      expect(
        (await backend.inspect(original))['blocks'][0]['runs'][0]['color'],
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
