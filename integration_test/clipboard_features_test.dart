import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/platform/clipboards.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
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
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (done()) return;
    }
    throw StateError('Timed out: $label');
  }

  EditorToolPanel panel(WidgetTester tester) =>
      tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
  Future<void> present(
    WidgetTester tester,
    DocumentBackend backend,
    Uint8List bytes,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: OfficeTheme.build(Brightness.light),
        home: NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: bytes, name: 'Clipboard.xlsx'),
        ),
      ),
    );
    await until(
      tester,
      () => find.byType(EditorToolPanel).evaluate().isNotEmpty,
      'loaded',
    );
    await tester.pumpAndSettle();
  }

  Future<void> tool(WidgetTester tester, String section, String name) async {
    final p = panel(tester);
    final i = p.sections.indexWhere((s) => s.label == section);
    final j = p.sections[i].tools.indexWhere((t) => t.label == name);
    tester.state<EditorToolPanelState>(find.byType(EditorToolPanel)).openTool(
      i,
      [j],
    );
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

  Future<void> select(WidgetTester tester, String area) async {
    await tool(tester, 'Данные', 'Выделить диапазон');
    await tester.enterText(find.byKey(const Key('grid-range-input')), area);
    await press(tester, 'Выделить ячейки');
    await tester.pumpAndSettle();
    await collapse(tester);
  }

  Future<void> copy(WidgetTester tester, String area) async {
    await select(tester, area);
    final command = panel(tester).sections
        .expand((s) => s.tools)
        .firstWhere((t) => t.label == 'Копировать');
    command.onPressed!();
    await until(
      tester,
      () => defaultGridClipboard.current != null,
      'Android rich clipboard',
    );
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String label) async {
    await tool(tester, 'Главная', 'Вставить');
    await press(tester, label);
    await until(tester, () => panel(tester).undo != null, 'checked paste');
    await tester.pumpAndSettle();
  }

  Future<Uint8List> save(WidgetTester tester) async {
    Uint8List? output;
    const channel = MethodChannel('flutter_file_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          output = Uint8List.fromList(
            (call.arguments as Map)['data'] as Uint8List,
          );
          return '/test/Clipboard.xlsx';
        });
    try {
      await collapse(tester);
      await tester.tap(find.byTooltip('Меню файла'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить копию'));
      await until(tester, () => output != null, 'XLSX export');
      await tester.pumpAndSettle();
      return output!;
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }

  Future<Map<String, dynamic>> cell(
    NativeDocumentBackend b,
    Uint8List bytes,
    String address, [
    int sheet = 0,
  ]) async =>
      (await b.inspectGrid(
            bytes,
            GridWindow(sheet, 0, 0),
            address,
          ))['selection']
          as Map<String, dynamic>;
  Future<Uint8List> source(NativeDocumentBackend b) async {
    var bytes = await b.create();
    for (final e in {'A1': '10', 'B1': '=A1*2'}.entries) {
      bytes = await b.edit(bytes, {
        'sheet': 0,
        'address': e.key,
        'value': e.value,
      });
    }
    return b.edit(bytes, {
      'action': 'format_range',
      'sheet': 0,
      'address': 'A1',
      'range': 'A1:B1',
      'style': {'bold': true, 'color': '#225599', 'numFmt': '0.00'},
    });
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    final bytes = await binding.takeScreenshot(name);
    final path = '${Directory.systemTemp.path}/aoc-$name.png';
    await File(path).writeAsBytes(bytes, flush: true);
    debugPrint('DESIGN_SCREENSHOT $path');
  }

  setUp(defaultGridClipboard.clearLocal);
  tearDown(defaultGridClipboard.clearLocal);

  testWidgets(
    'Rich Android clipboard survives source screen closure and pastes across workbooks and sheets with undo',
    (tester) async {
      final b = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(b.close);
      final original = await source(b);
      await present(tester, b, original);
      await copy(tester, 'A1:B1');
      var target = await b.create();
      target = await b.edit(target, {
        'action': 'add_sheet',
        'sheet': 0,
        'address': 'A1',
        'name': 'Target',
      });
      target = await b.edit(target, {
        'sheet': 1,
        'address': 'F1',
        'value': '=SUM(D3:E3)',
      });
      await present(tester, b, target);
      await select(tester, 'D3');
      await paste(tester, 'Вставить всё');
      final saved = await save(tester);
      expect((await cell(b, saved, 'D3', 1))['style']['bold'], true);
      expect((await cell(b, saved, 'D3', 1))['display'], '10.00');
      expect((await cell(b, saved, 'E3', 1))['input'], '=D3*2');
      expect((await cell(b, saved, 'F1', 1))['display'], '30');
      await tester.tap(find.byTooltip('Отменить'));
      await until(tester, () => panel(tester).redo != null, 'undo paste');
      expect((await cell(b, await save(tester), 'D3', 1))['input'], '');
      await tester.tap(find.byTooltip('Повторить'));
      await until(tester, () => panel(tester).undo != null, 'redo paste');
      await capture(tester, 'grid-rich-clipboard-024');
      await present(tester, b, saved);
      expect((await cell(b, saved, 'E3', 1))['input'], '=D3*2');
      expect((await cell(b, original, 'B1'))['input'], '=A1*2');
      expect((await cell(b, target, 'D3', 1))['input'], '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Values formulas and formats modes preserve destination counterparts after Android clipboard roundtrip',
    (tester) async {
      final b = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(b.close);
      final original = await source(b);
      await present(tester, b, original);
      await copy(tester, 'B1');
      var target = await b.create();
      target = await b.edit(target, {
        'sheet': 0,
        'address': 'D5',
        'value': '7',
      });
      target = await b.edit(target, {
        'sheet': 0,
        'address': 'E5',
        'value': '99',
      });
      target = await b.edit(target, {
        'action': 'format',
        'sheet': 0,
        'address': 'E5',
        'style': {'italic': true},
      });
      for (final entry in {
        'Только значения': '20',
        'Только формулы': '=D5*2',
        'Только оформление': '99',
      }.entries) {
        await present(tester, b, target);
        await select(tester, 'E5');
        await paste(tester, entry.key);
        final result = await cell(b, await save(tester), 'E5');
        expect(result['input'], entry.value);
        expect(result['style']['bold'], entry.key == 'Только оформление');
        if (entry.key != 'Только оформление') {
          expect(result['style']['italic'], true);
        }
      }
      await capture(tester, 'grid-paste-special-024');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'External identical TSV loses rich identity; quoted Unicode text and destination formatting survive export',
    (tester) async {
      final b = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(b.close);
      await present(tester, b, await source(b));
      await copy(tester, 'A1:B1');
      final plain = defaultGridClipboard.current!.text;
      await Clipboard.setData(ClipboardData(text: plain));
      var target = await b.create();
      target = await b.edit(target, {
        'action': 'format',
        'sheet': 0,
        'address': 'A1',
        'style': {'italic': true},
      });
      await present(tester, b, target);
      await paste(tester, 'Вставить всё');
      var saved = await save(tester);
      expect(defaultGridClipboard.current, isNull);
      expect((await cell(b, saved, 'A1'))['style']['italic'], true);
      expect((await cell(b, saved, 'A1'))['style']['bold'], false);
      expect((await cell(b, saved, 'B1'))['input'], '20');
      await Clipboard.setData(
        const ClipboardData(
          text: '"лево\tправо"\t12\r\n"строка1\nстрока2 😀"\t=1+2\n',
        ),
      );
      await present(tester, b, await b.create());
      await paste(tester, 'Вставить всё');
      saved = await save(tester);
      expect((await cell(b, saved, 'A1'))['input'], 'лево\tправо');
      expect((await cell(b, saved, 'A2'))['input'], 'строка1\nстрока2 😀');
      expect((await cell(b, saved, 'B2'))['display'], '3');
      await capture(tester, 'grid-external-clipboard-024');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
