import 'dart:convert';

import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show setup;
import 'office_features_backend.dart';

class _RejectedLineEditBackend extends FeaturesBackend {
  _RejectedLineEditBackend()
    : super({
        'sheets': [
          {'name': 'Sheet1', 'cells': <String, dynamic>{}},
        ],
      });

  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async {
    final result = await super.edit(bytes, request);
    if (request['action'] == 'line_structure') failInspect = true;
    return result;
  }
}

Future<void> tool(WidgetTester tester, String section, String name) async {
  final panel = tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
  final i = panel.sections.indexWhere((s) => s.label == section);
  final j = panel.sections[i].tools.indexWhere((t) => t.label == name);
  tester.state<EditorToolPanelState>(find.byType(EditorToolPanel)).openTool(i, [
    j,
  ]);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> historyAction(WidgetTester tester, bool undo) async {
  final collapse = find.byTooltip('Свернуть инструменты');
  if (collapse.evaluate().isNotEmpty) {
    await tester.tap(collapse);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byTooltip(undo ? 'Отменить' : 'Повторить'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Whole-line delete confirms exact selection and a failed preview leaves the pending edit undoable',
    (tester) async {
      final backend = _RejectedLineEditBackend();
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
        'A1:B2',
      );
      await press(tester, 'Выделить ячейки');
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'Draft');
      await tool(tester, 'Главная', 'Строки и столбцы');
      await press(tester, 'Удалить строки');
      expect(find.text('Будут удалены строки 1–2 целиком.'), findsOneWidget);
      expect(backend.requests, isEmpty);
      tester.state<EditorToolPanelState>(find.byType(EditorToolPanel)).back();
      await tester.pumpAndSettle();
      expect(backend.requests, isEmpty);
      await press(tester, 'Удалить строки');
      await press(tester, 'Удалить');
      expect(backend.requests, hasLength(2));
      expect(backend.requests.first['value'], 'Draft');
      expect(backend.requests.last, {
        'action': 'line_structure',
        'sheet': 0,
        'address': 'A1',
        'axis': 'rows',
        'operation': 'delete',
        'start': 0,
        'count': 2,
      });
      expect(tester.widget<TextField>(formula).controller!.text, 'Draft');
      await historyAction(tester, true);
      expect(tester.widget<TextField>(formula).controller!.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Word replacement is one undo step, supports Unicode and preserves state on failure',
    (tester) async {
      final backend = FeaturesBackend({
        'paragraphs': ['До cat 😀 cat'],
        'tables': 0,
        'blocks': [
          {
            'block': 0,
            'text': 'До cat 😀 cat',
            'editable': true,
            'runs': [
              {'text': 'До cat 😀 cat'},
            ],
          },
        ],
      });
      await setup(
        tester,
        const Size(320, 800),
        1.6,
        NativeWordScreen(
          backend: backend,
          launch: EditorLaunch(bytes: await backend.create()),
        ),
      );
      await tool(tester, 'Рецензирование', 'Найти и заменить');
      await tester.enterText(find.byKey(const Key('word-find-input')), 'cat');
      await tester.enterText(
        find.byKey(const Key('word-replace-input')),
        'кот',
      );
      await press(tester, 'Заменить все');
      expect(backend.requests.last['action'], 'replace_all');
      expect(backend.viewed!['paragraphs'], ['До кот 😀 кот']);
      await historyAction(tester, true);
      expect(backend.viewed!['paragraphs'], ['До cat 😀 cat']);
      await historyAction(tester, false);
      expect(backend.viewed!['paragraphs'], ['До кот 😀 кот']);
      await tool(tester, 'Рецензирование', 'Найти и заменить');
      await tester.enterText(find.byKey(const Key('word-find-input')), 'кот');
      backend.failEdit = true;
      await press(tester, 'Заменить все');
      expect(backend.viewed!['paragraphs'], ['До кот 😀 кот']);
      expect(
        tester.widget<EditorToolPanel>(find.byType(EditorToolPanel)).undo,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'New sheet flushes cell input, undo/redo restores sheet context, reopening uses saved active sheet',
    (tester) async {
      final backend = FeaturesBackend({
        'sheets': [
          {'name': 'Sheet1', 'cells': <String, dynamic>{}},
        ],
      });
      final initial = await backend.create();
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: initial),
        ),
      );
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'Keep A1');
      await tool(tester, 'Вставка', 'Новый лист');
      await tester.enterText(find.byKey(const Key('new-sheet-name')), 'Расчёт');
      await press(tester, 'Создать лист');
      expect(backend.viewed!['sheets'], hasLength(2));
      expect(backend.viewed!['sheets'][0]['cells']['A1']['input'], 'Keep A1');
      expect(tester.widget<TextField>(formula).controller!.text, '');
      await historyAction(tester, true);
      expect(backend.viewed!['sheets'], hasLength(1));
      expect(tester.widget<TextField>(formula).controller!.text, 'Keep A1');
      await historyAction(tester, false);
      expect(backend.viewed!['sheets'], hasLength(2));
      final saved = backend.encode(backend.viewed!);
      await tester.pumpWidget(const SizedBox.shrink());
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: saved),
        ),
      );
      expect(tester.widget<TextField>(formula).controller!.text, '');
      expect(backend.viewed!['activeSheet'], 1);
      expect(backend.decode(initial)['sheets'], hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Slide reorder is reversible and failed restore leaves history available for retry',
    (tester) async {
      final backend = FeaturesBackend({
        'width': 960,
        'height': 540,
        'slides': [
          for (var i = 0; i < 3; i++)
            {
              'index': i,
              'id': i,
              'title': 'Slide $i',
              'shapes': [
                {
                  'id': i + 1,
                  'text': 'Content $i',
                  'editableText': true,
                  'rect': {'x': 30, 'y': 30, 'w': 500, 'h': 100},
                },
              ],
            },
        ],
      });
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativeDeckScreen(
          backend: backend,
          launch: EditorLaunch(bytes: await backend.create()),
        ),
      );
      await tool(tester, 'Вид', 'Порядок слайдов');
      await press(tester, 'В конец');
      expect((backend.viewed!['slides'] as List).map((s) => s['id']), [
        1,
        2,
        0,
      ]);
      backend.failInspect = true;
      await historyAction(tester, true);
      expect(
        tester.widget<EditorToolPanel>(find.byType(EditorToolPanel)).undo,
        isNotNull,
      );
      await historyAction(tester, true);
      expect((backend.viewed!['slides'] as List).map((s) => s['id']), [
        0,
        1,
        2,
      ]);
      await historyAction(tester, false);
      expect((backend.viewed!['slides'] as List).map((s) => s['id']), [
        1,
        2,
        0,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Moving a slide commits an earlier text draft without changing the slide being moved',
    (tester) async {
      final backend = FeaturesBackend({
        'width': 960,
        'height': 540,
        'slides': [
          for (var i = 0; i < 3; i++)
            {
              'id': i,
              'shapes': [
                {
                  'id': i + 1,
                  'text': 'Content $i',
                  'editableText': true,
                  'rect': {'x': 30, 'y': 30, 'w': 500, 'h': 100},
                },
              ],
            },
        ],
      });
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativeDeckScreen(
          backend: backend,
          launch: EditorLaunch(bytes: await backend.create()),
        ),
      );
      await tool(tester, 'Главная', 'Текстовые объекты');
      await press(tester, 'Content 0');
      await tester.enterText(
        find.byKey(const Key('deck-text-input')),
        'Updated first slide',
      );
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      await tool(tester, 'Вид', 'Порядок слайдов');
      await press(tester, 'В конец');
      expect(backend.requests.last['action'], 'move_slide');
      expect(backend.requests.last['slide'], 1);
      expect((backend.viewed!['slides'] as List).map((s) => s['id']), [
        0,
        2,
        1,
      ]);
      expect(
        backend.viewed!['slides'][0]['shapes'][0]['text'],
        'Updated first slide',
      );
      await historyAction(tester, true);
      expect((backend.viewed!['slides'] as List).map((s) => s['id']), [
        0,
        1,
        2,
      ]);
      await historyAction(tester, true);
      expect(backend.viewed!['slides'][0]['shapes'][0]['text'], 'Content 0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PDF rotation uses displayed dimensions once and renderer failures do not consume undo',
    (tester) async {
      const channel = MethodChannel('artofficecraft/pdf_renderer');
      var session = 0, failRenderer = false;
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'openDocument') {
              if (failRenderer) {
                failRenderer = false;
                throw PlatformException(code: 'open_failed');
              }
              return {'session': ++session, 'pageCount': 3};
            }
            if (call.method == 'renderPage') return png;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final backend = FeaturesBackend({
        'pages': [
          for (var i = 0; i < 3; i++)
            {'index': i, 'width': 595, 'height': 842, 'rotation': 0},
        ],
      });
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativePdfScreen(
          backend: backend,
          renderer: PdfPageRenderer(allowNonAndroidForTesting: true),
          launch: EditorLaunch(bytes: await backend.create()),
        ),
      );
      await tool(tester, 'Страницы', 'Повернуть');
      await press(tester, 'Повернуть вправо');
      final page = tester.widget<PdfViewport>(find.byType(PdfViewport));
      expect(page.pageWidth, 842);
      expect(page.pageHeight, 595);
      failRenderer = true;
      await historyAction(tester, true);
      expect(
        tester.widget<PdfViewport>(find.byType(PdfViewport)).pageWidth,
        842,
      );
      expect(
        tester.widget<EditorToolPanel>(find.byType(EditorToolPanel)).undo,
        isNotNull,
      );
      await historyAction(tester, true);
      expect(
        tester.widget<PdfViewport>(find.byType(PdfViewport)).pageWidth,
        595,
      );
      await historyAction(tester, false);
      expect(
        tester.widget<PdfViewport>(find.byType(PdfViewport)).pageWidth,
        842,
      );
      await tool(tester, 'Страницы', 'Порядок страниц');
      final panel = tester.widget<EditorToolPanel>(
        find.byType(EditorToolPanel),
      );
      final sec = panel.sections.indexWhere((s) => s.label == 'Страницы');
      final order = panel.sections[sec].tools.indexWhere(
        (t) => t.label == 'Порядок страниц',
      );
      tester.state<EditorToolPanelState>(find.byType(EditorToolPanel)).openTool(
        sec,
        [order, 2],
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pdf-target-page')), '3');
      await press(tester, 'Переместить страницу');
      expect(backend.viewed!['pages'][2]['rotation'], 90);
      expect(tester.takeException(), isNull);
    },
  );
}
