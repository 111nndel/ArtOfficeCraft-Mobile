import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'grid_layout_fixture.dart';
import 'worker_media_fixture.dart';

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
    'Word exact Unicode replacement is saved, undoable and reopened through Rust',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.word);
      addTearDown(backend.close);
      final original = await backend.create('До cat 😀 cat');
      await present(
        tester,
        NativeWordScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Find.docx'),
        ),
      );
      await tool(tester, 'Рецензирование', 'Найти и заменить');
      await tester.enterText(find.byKey(const Key('word-find-input')), 'cat');
      await tester.enterText(
        find.byKey(const Key('word-replace-input')),
        'кот',
      );
      await press(tester, 'Заменить все');
      await until(
        tester,
        () => panel(tester).undo != null,
        'native replacement',
      );
      final replaced = await save(tester, 'Сохранить как DOCX');
      expect(
        (await backend.inspect(replaced))['paragraphs'],
        contains('До кот 😀 кот'),
      );
      await history(tester, true);
      final undone = await save(tester, 'Сохранить как DOCX');
      expect(
        (await backend.inspect(undone))['paragraphs'],
        contains('До cat 😀 cat'),
      );
      await history(tester, false);
      expect(
        (await backend.inspect(
          await save(tester, 'Сохранить как DOCX'),
        ))['paragraphs'],
        contains('До кот 😀 кот'),
      );
      expect(
        (await backend.inspect(original))['paragraphs'],
        contains('До cat 😀 cat'),
      );
      await tool(tester, 'Рецензирование', 'Найти и заменить');
      await capture(tester, 'word-find-replace-022');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'New XLSX tab commits pending input, restores sheet on undo and opens saved active tab',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      final original = gridLayoutFixture();
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Sheets.xlsx'),
        ),
      );
      Finder formula() => find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula(), 'Native pending input');
      await tool(tester, 'Вставка', 'Новый лист');
      await tester.enterText(
        find.byKey(const Key('new-sheet-name')),
        'Расчёт 😀',
      );
      await press(tester, 'Создать лист');
      await until(tester, () => panel(tester).undo != null, 'native new sheet');
      final added = await save(tester, 'Сохранить копию');
      final oldTab = await backend.inspectGrid(
        added,
        const GridWindow(0, 0, 0),
        'A1',
      );
      expect(oldTab['sheets'], hasLength(2));
      expect(oldTab['selection']['input'], 'Native pending input');
      expect(oldTab['activeSheet'], 1);
      await history(tester, true);
      final undone = await save(tester, 'Сохранить копию');
      expect(
        (await backend.inspectGrid(
          undone,
          const GridWindow(0, 0, 0),
          'A1',
        ))['sheets'],
        hasLength(1),
      );
      expect(
        tester.widget<TextField>(formula()).controller!.text,
        'Native pending input',
      );
      await history(tester, false);
      await present(
        tester,
        NativeGridScreen(
          backend: backend,
          launch: EditorLaunch(bytes: added, name: 'Reopened.xlsx'),
        ),
      );
      expect(tester.widget<TextField>(formula()).controller!.text, '');
      final input = await backend.inspectGrid(
        original,
        const GridWindow(0, 0, 0),
        'A1',
      );
      expect(input['sheets'], hasLength(1));
      expect(input['selection']['input'], 'Imported merged title');
      await capture(tester, 'new-sheet-reopened-022');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'PPTX ordering and undo preserve embedded image bytes after export',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.deck);
      addTearDown(backend.close);
      final original = workerMediaDeck;
      await present(
        tester,
        NativeDeckScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Order.pptx'),
        ),
      );
      await tool(tester, 'Вид', 'Порядок слайдов');
      await press(tester, 'В конец');
      await until(
        tester,
        () => panel(tester).undo != null,
        'native slide reorder',
      );
      final moved = await save(tester, 'Сохранить копию PPTX');
      final preview = await backend.inspect(moved);
      final picture = (preview['slides'][0]['shapes'] as List).firstWhere(
        (s) => s['imageId'] != null,
      );
      expect(
        await backend.image(moved, 0, picture['imageId'] as int),
        workerMediaPng,
      );
      await history(tester, true);
      final undone = await save(tester, 'Сохранить копию PPTX');
      final before = await backend.inspect(undone);
      final restored = (before['slides'][1]['shapes'] as List).firstWhere(
        (s) => s['imageId'] != null,
      );
      expect(
        await backend.image(undone, 1, restored['imageId'] as int),
        workerMediaPng,
      );
      await history(tester, false);
      await capture(tester, 'slide-order-redone-022');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'PDF native rotation fits landscape, arbitrary reorder and undo survive export',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
      addTearDown(backend.close);
      var original = await backend.create();
      original = await backend.edit(original, {
        'action': 'insert_blank',
        'page': 0,
      });
      original = await backend.edit(original, {
        'action': 'insert_blank',
        'page': 1,
      });
      await present(
        tester,
        NativePdfScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Pages.pdf'),
        ),
      );
      await tool(tester, 'Страницы', 'Повернуть');
      await press(tester, 'Повернуть вправо');
      await until(
        tester,
        () => panel(tester).undo != null,
        'native page rotation',
      );
      var viewport = tester.widget<PdfViewport>(find.byType(PdfViewport));
      expect(viewport.pageWidth, greaterThan(viewport.pageHeight));
      await tool(tester, 'Страницы', 'Порядок страниц', child: 2);
      await tester.enterText(find.byKey(const Key('pdf-target-page')), '3');
      await press(tester, 'Переместить страницу');
      await until(tester, () => panel(tester).undo != null, 'native page move');
      final moved = await save(tester, 'Сохранить PDF');
      final pages = (await backend.inspect(moved))['pages'] as List;
      expect(pages[2]['rotation'], 90);
      expect(pages[0]['rotation'], 0);
      await history(tester, true);
      final undone =
          (await backend.inspect(await save(tester, 'Сохранить PDF')))['pages']
              as List;
      expect(undone[0]['rotation'], 90);
      viewport = tester.widget<PdfViewport>(find.byType(PdfViewport));
      expect(viewport.pageWidth, greaterThan(viewport.pageHeight));
      await history(tester, false);
      await capture(tester, 'pdf-page-order-022');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
