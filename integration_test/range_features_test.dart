import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
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
