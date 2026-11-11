import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/native/grid_selection.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show setup;
import 'office_features_backend.dart';
import 'office_features_test.dart' show tool, press, historyAction;
import 'localization_test.dart' show englishApp;

class MergeBackend extends FeaturesBackend implements GridDocuments {
  MergeBackend({
    Map<String, dynamic> other = const {},
    bool protected = false,
    bool table = false,
  }) : super({
         'sheets': [
           {
             'name': 'Data',
             'protected': protected,
             'cells': {
               'A1': {
                 'input': 'original',
                 'display': 'original',
                 'style': {'bold': true},
               },
               ...other,
             },
           },
         ],
         'layout': {
           'defaultRowHeight': 20,
           'defaultColumnWidth': 64,
           'merges': [],
           'tables': table
               ? [
                   [0, 0, 2, 1],
                 ]
               : [],
         },
       });
  final windows = <GridWindow>[];
  bool rejectPreview = false;
  @override
  Future<Map<String, dynamic>> gridView(
    Uint8List bytes,
    GridWindow w,
    String selected,
  ) async {
    windows.add(w);
    if (w.columns > 2048) throw StateError('Native column bound exceeded');
    final data = await super.inspect(bytes);
    final full = data['sheets'][w.sheet]['cells'] as Map;
    final layout = GridLayout.fromJson(data['layout'] as Map?);
    final at = gridAddress(selected)!;
    final merge = layout.mergeAt(at.row, at.column);
    final canonical = merge == null
        ? selected
        : '${gridColumnName(merge.column)}${merge.row + 1}';
    Map<String, dynamic> record(String address) => {
      ...Map<String, dynamic>.from(
        full[address] as Map? ?? {'input': '', 'display': ''},
      ),
      'address': address,
    };
    data['selection'] = record(canonical);
    data['sheets'][w.sheet]['cells'] = {
      for (final key in full.keys.cast<String>())
        if (w.contains(gridAddress(key)!.row, gridAddress(key)!.column))
          key: record(key),
    };
    return data;
  }

  @override
  Future<DocumentSnapshot> editGridView(
    Uint8List bytes,
    Map<String, dynamic> request,
    GridWindow window,
    String selected,
  ) async {
    final changed = await edit(bytes, request);
    return DocumentSnapshot(changed, await gridView(changed, window, selected));
  }

  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async {
    if (request['action'] != 'merge_range') return super.edit(bytes, request);
    requests.add(Map.of(request));
    if (failEdit) throw StateError('Merge failed');
    final data = decode(bytes);
    final cells = dataCells(data);
    final range = GridSelection.parse(request['range'] as String)!;
    final anchor = '${gridColumnName(range.column)}${range.row + 1}';
    if (request.containsKey('value')) {
      final address = request['address'] as String;
      cells[address] = {
        ...?cells[address] as Map?,
        'input': request['value'],
        'display': request['value'],
      };
    }
    if (request['mode'] != 'unmerge') {
      for (final key in cells.keys.toList()) {
        final at = gridAddress(key as String)!;
        if (key != anchor &&
            at.row >= range.row &&
            at.row <= range.endRow &&
            at.column >= range.column &&
            at.column <= range.endColumn) {
          cells[key] = {
            ...cells[key] as Map,
            'input': '',
            'display': '',
            'formula': false,
            'hasContent': false,
          };
        }
      }
      if (request['mode'] == 'center') {
        cells[anchor] = {
          ...?cells[anchor] as Map?,
          'style': {...?cells[anchor]?['style'] as Map?, 'align': 'center'},
        };
      }
    }
    data['sheets'][0]['cells'] = cells;
    data['layout']['merges'] = request['mode'] == 'unmerge'
        ? []
        : [
            [range.row, range.column, range.endRow, range.endColumn],
          ];
    if (rejectPreview) {
      rejectPreview = false;
      failInspect = true;
    }
    return encode(data);
  }

  Map dataCells(Map data) => data['sheets'][0]['cells'] as Map;
}

Finder get formula => find.descendant(
  of: find.byKey(const Key('formula-input')),
  matching: find.byType(TextField),
);
Future<void> open(
  WidgetTester tester,
  MergeBackend backend, {
  bool english = false,
}) async {
  final screen = NativeGridScreen(
    backend: backend,
    launch: EditorLaunch(bytes: await backend.create()),
  );
  if (english) {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(englishApp(screen));
    await tester.pumpAndSettle();
  } else {
    await setup(tester, const Size(320, 800), 1.6, screen);
  }
}

Future<void> mergePane(WidgetTester tester) async {
  await tool(tester, 'Главная', 'Формат ячейки');
  final p = tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
  final section = p.sections.indexWhere((s) => s.label == 'Главная');
  final format = p.sections[section].tools.indexWhere(
    (t) => t.label == 'Формат ячейки',
  );
  final child = p.sections[section].tools[format].children!.indexWhere(
    (t) => t.label == 'Объединение ячеек',
  );
  tester.state<EditorToolPanelState>(find.byType(EditorToolPanel)).openTool(
    section,
    [format, child],
  );
  await tester.pumpAndSettle();
}

Future<void> select(
  WidgetTester tester,
  String range, {
  bool english = false,
}) async {
  await mergePane(tester);
  await tester.enterText(find.byKey(const Key('grid-merge-range')), range);
  await press(tester, english ? 'Select cells' : 'Выделить ячейки');
}

Future<void> confirm(WidgetTester tester, {bool english = false}) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(english ? 'Merge' : 'Объединить'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Merge combines a pending draft into one undo step and unmerges without losing style',
    (tester) async {
      final backend = MergeBackend();
      await open(tester, backend);
      await select(tester, 'A1:B2');
      await tester.enterText(formula, 'changed');
      await press(tester, 'Объединить и выровнять по центру');
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.requests, hasLength(1));
      expect(backend.requests.single, containsPair('value', 'changed'));
      expect(backend.requests.single['action'], 'merge_range');
      expect(tester.widget<TextField>(formula).controller!.text, 'changed');
      await historyAction(tester, true);
      expect(tester.widget<TextField>(formula).controller!.text, 'original');
      await historyAction(tester, false);
      expect(tester.widget<TextField>(formula).controller!.text, 'changed');
      await mergePane(tester);
      await press(tester, 'Разъединить');
      expect(backend.viewed!['layout']['merges'], isEmpty);
      expect(
        backend.viewed!['sheets'][0]['cells']['A1']['style']['bold'],
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Cancellation preserves the draft; confirmed hidden contents are cleared and restored by undo',
    (tester) async {
      final backend = MergeBackend(
        other: {
          'B1': {'input': '', 'display': '', 'hasContent': true},
        },
      );
      await open(tester, backend);
      await select(tester, 'A1:B2');
      await tester.enterText(formula, 'new draft');
      await press(tester, 'Объединить');
      expect(
        find.text('Останется содержимое ячейки A1. Будет очищено ячеек: 1.'),
        findsOneWidget,
      );
      expect(backend.requests, isEmpty);
      await press(tester, 'Отмена');
      expect(tester.widget<TextField>(formula).controller!.text, 'new draft');
      expect(backend.requests, isEmpty);
      await press(tester, 'Объединить');
      await confirm(tester);
      expect(backend.requests.single['allowContentLoss'], true);
      await historyAction(tester, true);
      expect(backend.viewed!['sheets'][0]['cells']['B1']['hasContent'], true);
      expect(tester.widget<TextField>(formula).controller!.text, 'original');
    },
  );
  testWidgets(
    'A rejected checked merge preview keeps the pending draft and the old undo history',
    (tester) async {
      final backend = MergeBackend()..rejectPreview = true;
      await open(tester, backend);
      await select(tester, 'A1:B2');
      await tester.enterText(formula, 'retry draft');
      await press(tester, 'Объединить');
      expect(tester.widget<TextField>(formula).controller!.text, 'retry draft');
      expect(backend.viewed!['layout']['merges'], isEmpty);
      await press(tester, 'Объединить');
      expect(backend.requests, hasLength(2));
      expect(backend.requests.every((r) => r['action'] == 'merge_range'), true);
      await historyAction(tester, true);
      expect(tester.widget<TextField>(formula).controller!.text, 'original');
      expect(backend.viewed!['layout']['merges'], isEmpty);
    },
  );
  testWidgets(
    'Wide offscreen confirmation uses bounded windows including empty-looking content',
    (tester) async {
      final last = '${gridColumnName(4095)}1';
      final backend = MergeBackend(
        other: {
          last: {'input': '', 'display': '', 'hasContent': true},
        },
      );
      await open(tester, backend);
      await select(tester, 'A1:$last');
      final reads = backend.windows.length;
      await press(tester, 'Объединить');
      expect(backend.windows.skip(reads), hasLength(2));
      expect(backend.windows.skip(reads).every((w) => w.columns <= 2048), true);
      expect(
        find.text('Останется содержимое ячейки A1. Будет очищено ячеек: 1.'),
        findsOneWidget,
      );
      await press(tester, 'Отмена');
      expect(backend.requests, isEmpty);
    },
  );
  testWidgets(
    'Protected sheets and Excel tables disable merge actions; English confirmation keeps addresses',
    (tester) async {
      final locked = MergeBackend(protected: true);
      await open(tester, locked);
      await select(tester, 'A1:B2');
      expect(find.text('Лист защищён'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Объединить'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final table = MergeBackend(table: true);
      await open(tester, table);
      await select(tester, 'A1:B2');
      expect(
        find.text('Объединение и разъединение недоступны внутри таблицы Excel'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Объединить'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final backend = MergeBackend(
        other: {
          'B1': {'input': 'keep', 'display': 'keep'},
        },
      );
      await open(tester, backend, english: true);
      await select(tester, 'A1:B2', english: true);
      await press(tester, 'Merge');
      expect(
        find.text('Only the contents of A1 will remain. Cells to clear: 1.'),
        findsOneWidget,
      );
      await confirm(tester, english: true);
      expect(backend.requests.single['allowContentLoss'], true);
    },
  );
}
