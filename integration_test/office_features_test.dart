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
  var screenshotSurfaceReady = false;
  setUp(() => screenshotSurfaceReady = false);
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
    // The integration binding restores the surface at the end of each test.
    if (!screenshotSurfaceReady) {
      await binding.convertFlutterSurfaceToImage();
      screenshotSurfaceReady = true;
    }
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

  Future<void> readingMode(
    WidgetTester tester,
    String section,
    String mode,
  ) async {
    await tool(tester, section, 'Режим чтения');
    await press(tester, mode);
    await collapse(tester);
  }

  testWidgets(
    'Android PDF swipes on both axes, scrolls a lazy strip, and remembers its mode',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
      addTearDown(backend.close);
      var bytes = await backend.create();
      for (var i = 0; i < 4; i++) {
        bytes = await backend.edit(bytes, {
          'action': 'insert_blank',
          'page': i,
        });
      }
      Widget pdf() => NativePdfScreen(
        backend: backend,
        launch: EditorLaunch(bytes: bytes, name: 'Reading.pdf'),
      );
      await present(tester, pdf());
      await readingMode(tester, 'Чтение', 'По одной, горизонтально');
      final canvas = find.byKey(const Key('pdf-viewport'));
      await tester.drag(canvas, const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(find.text('Страница 2 из 5'), findsOneWidget);

      await readingMode(tester, 'Чтение', 'По одной, вертикально');
      await tool(tester, 'Чтение', 'Масштаб');
      await press(tester, 'Вся страница');
      await collapse(tester);
      await tester.drag(canvas, const Offset(0, -190));
      await tester.pumpAndSettle();
      expect(find.text('Страница 3 из 5'), findsOneWidget);

      await readingMode(tester, 'Чтение', 'Непрерывно вниз');
      final strip = find.byKey(const Key('continuous-pages'));
      expect(find.text('Страница 3 из 5'), findsOneWidget);
      expect(
        find.byType(PdfPageImage).evaluate().length,
        greaterThanOrEqualTo(2),
      );
      await capture(tester, 'pdf-continuous-026');
      for (var i = 0; i < 2; i++) {
        await tester.drag(strip, const Offset(0, -320));
        await tester.pumpAndSettle();
      }
      expect(find.text('Страница 3 из 5'), findsNothing);
      await present(tester, pdf());
      await until(tester, () => strip.evaluate().isNotEmpty, 'saved PDF mode');
      expect(find.text('Страница 1 из 5'), findsOneWidget);
      await readingMode(tester, 'Чтение', 'По одной, горизонтально');
      await tool(tester, 'Чтение', 'Перейти к странице');
      await tester.enterText(find.byKey(const Key('reader-jump-number')), '5');
      await press(tester, 'Перейти к странице');
      await tester.pumpAndSettle();
      expect(find.text('Страница 5 из 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Android PPTX canvas swipes slides horizontally, vertically and in a continuous strip',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.deck);
      addTearDown(backend.close);
      var bytes = await backend.create();
      for (var i = 2; i <= 5; i++) {
        bytes = await backend.edit(bytes, {
          'action': 'add_slide',
          'text': 'Slide $i',
        });
      }
      await present(
        tester,
        NativeDeckScreen(
          backend: backend,
          launch: EditorLaunch(bytes: bytes, name: 'Reading.pptx'),
        ),
      );
      await readingMode(tester, 'Вид', 'По одной, горизонтально');
      final canvas = find.byKey(const Key('deck-viewport'));
      await tester.drag(canvas, const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(find.text('Слайд 2 из 5'), findsOneWidget);
      await readingMode(tester, 'Вид', 'По одной, вертикально');
      await tester.drag(canvas, const Offset(0, -170));
      await tester.pumpAndSettle();
      expect(find.text('Слайд 3 из 5'), findsOneWidget);
      await tool(tester, 'Вид', 'Режим чтения');
      await capture(tester, 'deck-reader-modes-026');
      await press(tester, 'Непрерывно вниз');
      await collapse(tester);
      final strip = find.byKey(const Key('continuous-pages'));
      expect(find.text('Слайд 3 из 5'), findsOneWidget);
      expect(
        find
            .descendant(of: strip, matching: find.byType(AspectRatio))
            .evaluate()
            .length,
        greaterThanOrEqualTo(2),
      );
      await tester.drag(strip, const Offset(0, -290));
      await tester.pumpAndSettle();
      expect(find.text('Слайд 3 из 5'), findsNothing);
      await capture(tester, 'deck-continuous-026');
      await readingMode(tester, 'Вид', 'По одной, горизонтально');
      expect(tester.takeException(), isNull);
      await tool(tester, 'Вид', 'Перейти к слайду');
      await tester.enterText(find.byKey(const Key('reader-jump-number')), '1');
      await press(tester, 'Перейти к слайду');
      await tester.pumpAndSettle();
      expect(find.text('Слайд 1 из 5'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
