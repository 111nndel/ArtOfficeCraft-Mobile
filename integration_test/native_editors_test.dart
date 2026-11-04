import 'package:artofficecraft_mobile/native/grid_layout.dart';

import 'grid_layout_fixture.dart';
import 'worker_media_fixture.dart';

import 'package:artofficecraft_mobile/native/grid_window.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:artofficecraft_mobile/l10n/app_strings.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/main.dart' show ArtOfficeCraftApp;

import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/native/native_build_info.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final bytes = await binding.takeScreenshot(name);
    final path = '${Directory.systemTemp.path}/aoc-$name.png';
    await File(path).writeAsBytes(bytes, flush: true);
    debugPrint('DESIGN_SCREENSHOT $path');
  }

  testWidgets(
    'Actual Android Rust engines: create, edit, reopen, native views',
    (tester) async {
      await tester.pumpWidget(const ArtOfficeCraftApp(initialLanguage: 'ru'));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture(tester, 'home');
      final word = NativeDocumentBackend.tryOpen(NativeDocumentKind.word)!;
      addTearDown(() => closeDocumentBackend(word));
      var doc = await word.create('Нативный тест Android');
      doc = await word.edit(doc, {
        'action': 'paragraph',
        'block': 0,
        'text': 'Изменено на Android',
        'char': {'bold': true},
        'align': 'justify',
      });
      final inspected = await word.inspect(doc);
      expect(inspected['paragraphs'], contains('Изменено на Android'));
      expect((inspected['blocks'] as List).first['runs'][0]['bold'], isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeWordScreen(
            launch: EditorLaunch(bytes: doc, name: 'Проверка.docx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Изменено на Android'), findsWidgets);
      await tester.tap(find.text('Изменено на Android'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        'Проверка клавиатуры Android',
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('word-inline-input')),
      );
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Развернуть инструменты'));
      await tester.pumpAndSettle();
      await capture(tester, 'word-tools');
      await tester.ensureVisible(find.byTooltip('Курсив'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Курсив'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 &&
            tester
                .widget<TextField>(find.byKey(const Key('word-inline-input')))
                .readOnly;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('word-inline-input')))
            .readOnly,
        isFalse,
      );
      expect(find.byKey(const Key('word-inline-input')), findsOneWidget);
      await tester.tap(find.byKey(const Key('word-inline-input')));
      await tester.pumpAndSettle();
      const finalText = 'Проверка клавиатуры Android 😀 сохранено';
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        finalText,
      );
      await tester.pump();
      expect(field.controller!.text, finalText, reason: 'before collapse');
      final saveDirectory = await Directory.systemTemp.createTemp(
        'aoc-inline-save-',
      );
      final savedFile = File('${saveDirectory.path}/edited.docx');
      const files = MethodChannel('flutter_file_dialog');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            expect(call.method, 'saveFile');
            await savedFile.writeAsBytes(
              (call.arguments as Map)['data'] as Uint8List,
              flush: true,
            );
            return savedFile.path;
          });
      try {
        await tester.tap(find.byTooltip('Свернуть инструменты'));
        await tester.pumpAndSettle();
        expect(field.controller!.text, finalText, reason: 'after collapse');
        await tester.tap(find.byTooltip('Меню файла'));
        await tester.pumpAndSettle();
        expect(field.controller!.text, finalText, reason: 'after file menu');
        await tester.tap(find.text('Сохранить как DOCX'));
        await tester.pumpAndSettle();
        final saved = await word.inspect(await savedFile.readAsBytes());
        expect(saved['paragraphs'], contains(finalText));
        expect((saved['blocks'] as List).first['runs'][0]['italic'], isTrue);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null);
        await saveDirectory.delete(recursive: true);
      }
      expect(find.text(finalText), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(find.text('Проверка клавиатуры Android'), findsWidgets);
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text(finalText), findsWidgets);

      final grid = NativeDocumentBackend.tryOpen(NativeDocumentKind.grid)!;
      addTearDown(() => closeDocumentBackend(grid));
      var book = await grid.create();
      for (final entry in {
        'A1': '12',
        'B1': '8',
        'C1': '=SUM(A1:B1)',
      }.entries) {
        book = await grid.edit(book, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      final cells =
          ((await grid.inspect(book))['sheets'] as List).first['cells'] as Map;
      expect(cells['C1']['display'], '20');
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeGridScreen(
            launch: EditorLaunch(bytes: book, name: 'Проверка.xlsx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'grid-collapsed');
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await capture(tester, 'grid-section-menu');
      await tester.tap(find.text('Данные'));
      await tester.pumpAndSettle();
      await capture(tester, 'grid-data');
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      expect(find.text('20'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('grid-cell-A1')));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '15');
      await tester.tap(find.byTooltip('Применить'));
      await tester.pumpAndSettle();
      expect(find.text('23'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('grid-cell-A1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0,5');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '0,5',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('tool-section-caption')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Жирный'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Формат ячейки'));
      await tester.tap(find.text('Формат ячейки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Числовой формат'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Процентный'));
      await tester.tap(find.text('Процентный'));
      await tester.pumpAndSettle();
      await capture(tester, 'grid-percent');
      expect(find.text('50.00%'), findsOneWidget);
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grid-cell-A1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0,75');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '0,75',
      );
      await tester.pump();
      Uint8List? gridExport;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            gridExport = (call.arguments as Map)['data'] as Uint8List;
            return '/test/saved.xlsx';
          });
      try {
        await tester.tap(find.byTooltip('Меню файла'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранить копию'));
        await tester.pumpAndSettle();
        final reread = await grid.inspect(gridExport!);
        final c = reread['sheets'][0]['cells']['A1'];
        expect(c['input'], '0.75');
        expect(c['display'], '75.00%');
        expect(c['style']['bold'], isTrue);
        expect(c['style']['numFmt'], '0.00%');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null);
      }
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(find.text('50.00%'), findsOneWidget);
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('75.00%'), findsOneWidget);

      final deck = NativeDocumentBackend.tryOpen(NativeDocumentKind.deck)!;
      addTearDown(() => closeDocumentBackend(deck));
      var slides = await deck.create();
      slides = await deck.edit(slides, {
        'action': 'add_text',
        'slide': 0,
        'text': 'Настоящий PPTX',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeDeckScreen(
            launch: EditorLaunch(bytes: slides, name: 'Проверка.pptx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Настоящий PPTX'), findsWidgets);
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вставка'));
      await tester.pumpAndSettle();
      await capture(tester, 'deck-insert');
      await tester.tap(find.text('Текстовый блок'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('deck-text-input')),
        'Прямо в плашке',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'deck-text-form');
      await tester.ensureVisible(find.text('Применить'));
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(find.text('Прямо в плашке'), findsWidgets);
      expect(tester.takeException(), isNull);

      final pdf = NativeDocumentBackend.tryOpen(NativeDocumentKind.pdf)!;
      addTearDown(() => closeDocumentBackend(pdf));
      Uint8List pages = await pdf.create();
      pages = await pdf.edit(pages, {'action': 'duplicate', 'page': 0});
      expect(((await pdf.inspect(pages))['pages'] as List).length, 2);
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativePdfScreen(
            launch: EditorLaunch(bytes: pages, name: 'Проверка.pdf'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Страница 1 из 2'), findsWidgets);
      await tester.tap(find.text('Чтение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Страницы'));
      await tester.pumpAndSettle();
      await capture(tester, 'pdf-pages');
      expect(tester.takeException(), isNull);

      final info = await readNativeBuildInfo();
      expect(info!['abi'], 1);
      expect(info['coreVersion'], '0.22.0');
      expect((info['engines'] as Map).keys.toSet(), {
        'wordcraft',
        'gridcraft',
        'deckcraft',
        'pdfcraft',
      });

      // Exercise actual Android filesystem persistence, then parse fresh bytes.
      // Android's interactive SAF picker is a separate manual check.
      final directory = await Directory.systemTemp.createTemp('aoc-roundtrip-');
      try {
        for (final entry in {
          'docx': (word, doc),
          'xlsx': (grid, book),
          'pptx': (deck, slides),
          'pdf': (pdf, pages),
        }.entries) {
          final file = File('${directory.path}/roundtrip.${entry.key}');
          await file.writeAsBytes(entry.value.$2, flush: true);
          final reopened = await file.readAsBytes();
          expect(reopened, orderedEquals(entry.value.$2));
          final summary = await entry.value.$1.inspect(reopened);
          switch (entry.key) {
            case 'docx':
              expect(summary['paragraphs'], contains('Изменено на Android'));
            case 'xlsx':
              expect(
                (summary['sheets'] as List).first['cells']['C1']['display'],
                '20',
              );
            case 'pptx':
              expect(
                (summary['slides'] as List).first['shapes'].toString(),
                contains('Настоящий PPTX'),
              );
            case 'pdf':
              expect((summary['pages'] as List).length, 2);
          }
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Actual Android: raw editor journals survive fresh stores and editor instances',
    (tester) async {
      for (final kind in EditorKind.values) {
        final root = await Directory.systemTemp.createTemp(
          'aoc-native-recovery-',
        );
        final nativeKind = switch (kind) {
          EditorKind.word => NativeDocumentKind.word,
          EditorKind.excel => NativeDocumentKind.grid,
          EditorKind.slides => NativeDocumentKind.deck,
          EditorKind.pdf => NativeDocumentKind.pdf,
        };
        final backend = NativeDocumentBackend.tryOpen(nativeKind)!;
        addTearDown(() => closeDocumentBackend(backend));
        final base = await backend.create(
          kind == EditorKind.word ? 'Сохранённая основа' : '',
        );
        final drafts = DraftStore(directory: root);
        final session = DraftSession(drafts, kind);
        Widget screen(EditorLaunch launch, DraftSession draft) =>
            switch (kind) {
              EditorKind.word => NativeWordScreen(
                backend: backend,
                launch: launch,
                draft: draft,
              ),
              EditorKind.excel => NativeGridScreen(
                backend: backend,
                launch: launch,
                draft: draft,
              ),
              EditorKind.slides => NativeDeckScreen(
                backend: backend,
                launch: launch,
                draft: draft,
              ),
              EditorKind.pdf => NativePdfScreen(
                backend: backend,
                launch: launch,
                draft: draft,
              ),
            };
        Future<void> mount(EditorLaunch launch, DraftSession draft) async {
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: OfficeTheme.build(Brightness.light),
              home: screen(launch, draft),
            ),
          );
          await tester.pumpAndSettle();
        }

        DraftSession? resumed;
        try {
          await mount(
            EditorLaunch(bytes: base, name: 'Recovery.${kind.extension}'),
            session,
          );
          const raw = 'RAW_RECOVERY_014 😀';
          if (kind == EditorKind.word) {
            await tester.tap(find.text('Сохранённая основа'));
            await tester.pumpAndSettle();
          } else if (kind == EditorKind.excel) {
            await tester.tap(find.byKey(const ValueKey('grid-cell-B1')));
            await tester.pumpAndSettle();
          } else if (kind == EditorKind.slides) {
            await tester.tap(find.text('Главная'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Вставка'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Текстовый блок'));
            await tester.pumpAndSettle();
          } else {
            await tester.tap(find.text('Чтение'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Страницы'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Дублировать'));
            await tester.pumpAndSettle();
          }
          final input = kind == EditorKind.word
              ? find.byKey(const Key('word-inline-input'))
              : kind == EditorKind.slides
              ? find.byKey(const Key('deck-text-input'))
              : find.byType(TextField);
          if (kind != EditorKind.pdf) {
            await tester.tap(input);
            await tester.pumpAndSettle();
            await tester.enterText(input, raw);
            await tester.pump();
          }
          await session.flush();
          await tester.pumpWidget(const SizedBox.shrink());
          await session.close();
          final reopened = DraftStore(directory: root);
          await reopened.load();
          expect(reopened.items, hasLength(1));
          final saved = await reopened.read(reopened.items.single.id);
          final report = await backend.inspect(saved.bytes);
          if (kind == EditorKind.word) {
            expect(report['paragraphs'], contains('Сохранённая основа'));
          }
          if (kind == EditorKind.excel) {
            expect(
              (report['sheets'][0]['cells'] as Map).containsKey('B1'),
              isFalse,
            );
          }
          resumed = DraftSession(reopened, kind, id: saved.info.id);
          await mount(
            EditorLaunch(
              bytes: saved.bytes,
              name: saved.info.name,
              recovery: saved.editor,
            ),
            resumed,
          );
          if (kind == EditorKind.pdf) {
            expect(find.text('Страница 2 из 2'), findsOneWidget);
          } else {
            expect(tester.widget<TextField>(input).controller!.text, raw);
          }
          await resumed.discard();
          await tester.pumpWidget(const SizedBox.shrink());
          await resumed.close();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await session.close();
          await resumed?.close();
          await root.delete(recursive: true);
        }
      }
    },
  );
  testWidgets(
    'Actual Android: English UI keeps document text and pinch zoom keeps pending input',
    (tester) async {
      Widget englishScreen(Widget child) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: OfficeTheme.build(Brightness.light),
        home: child,
      );
      Future<void> pinchCanvas(Finder target) async {
        final center = tester.getCenter(target);
        final first = await tester.createGesture(pointer: 1);
        final second = await tester.createGesture(pointer: 2);
        await first.down(center - const Offset(35, 0));
        await second.down(center + const Offset(35, 0));
        await tester.pump();
        for (var step = 1; step <= 5; step++) {
          final distance = 35.0 + 10 * step;
          await first.moveTo(center - Offset(distance, 0));
          await second.moveTo(center + Offset(distance, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
      }

      final word = NativeDocumentBackend.tryOpen(NativeDocumentKind.word)!;
      addTearDown(() => closeDocumentBackend(word));
      final docx = await word.create('Главная');
      await tester.pumpWidget(
        englishScreen(
          NativeWordScreen(
            backend: word,
            launch: EditorLaunch(bytes: docx, name: 'Документ.docx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      expect(find.text('Документ.docx'), findsOneWidget);
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      final grid = NativeDocumentBackend.tryOpen(NativeDocumentKind.grid)!;
      addTearDown(() => closeDocumentBackend(grid));
      final xlsx = await grid.create();
      await tester.pumpWidget(
        englishScreen(
          NativeGridScreen(
            backend: grid,
            launch: EditorLaunch(bytes: xlsx, name: 'Pinch.xlsx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grid-cell-A1')));
      await tester.pumpAndSettle();
      const pending = 'Unapplied 0.15 😀';
      await tester.enterText(find.byType(TextField), pending);
      await tester.pump();
      await pinchCanvas(find.byKey(const Key('sheet-viewport')));
      expect(
        tester.state<SheetViewportState>(find.byType(SheetViewport)).zoom,
        greaterThan(1.2),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        pending,
      );
      await tester.tap(find.byKey(const Key('tool-section-caption')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zoom'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('150%'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('150%'));
      await tester.pumpAndSettle();
      expect(
        tester.state<SheetViewportState>(find.byType(SheetViewport)).zoom,
        closeTo(1.5, .001),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        pending,
      );
      await capture(tester, 'english-grid-zoom');

      final pdf = NativeDocumentBackend.tryOpen(NativeDocumentKind.pdf)!;
      addTearDown(() => closeDocumentBackend(pdf));
      final bytes = await pdf.create();
      await tester.pumpWidget(
        englishScreen(
          NativePdfScreen(
            backend: pdf,
            launch: EditorLaunch(bytes: bytes, name: 'Full width.pdf'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.widget<PdfViewport>(find.byType(PdfViewport));
      final view = tester.state<PdfViewportState>(find.byType(PdfViewport));
      final canvas = tester.getSize(find.byKey(const Key('pdf-viewport')));
      expect(
        view.transform.value.getMaxScaleOnAxis() * page.pageWidth,
        closeTo(canvas.width - 16, .01),
      );
      expect(find.text('Page 1 of 1'), findsOneWidget);
      await capture(tester, 'english-pdf-width');
      final before = view.transform.value.getMaxScaleOnAxis();
      await pinchCanvas(find.byKey(const Key('pdf-viewport')));
      expect(view.transform.value.getMaxScaleOnAxis(), greaterThan(before));
      await tester.tap(find.byTooltip('Page thumbnails'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Actual Android: owned workers validate edits, reuse input and close for all four engines',
    (tester) async {
      for (final kind in NativeDocumentKind.values) {
        final backend = NativeDocumentBackend(kind);
        addTearDown(backend.close);
        final original = await backend.create('Worker original');
        final before = await backend.inspect(original);
        expect(await backend.inspect(original), before);
        expect(backend.workerStarts, 1);
        expect(backend.inputTransfers, 1);
        await expectLater(
          backend.editInspected(original, {'action': 'not-supported'}),
          throwsFormatException,
        );
        expect(await backend.inspect(original), before);
        final request = switch (kind) {
          NativeDocumentKind.word => <String, dynamic>{
            'action': 'paragraph',
            'block': 0,
            'text': 'Worker changed 😀',
          },
          NativeDocumentKind.grid => <String, dynamic>{
            'sheet': 0,
            'address': 'A1',
            'value': '42',
          },
          NativeDocumentKind.deck => <String, dynamic>{
            'action': 'add_text',
            'slide': 0,
            'text': 'Worker changed 😀',
          },
          NativeDocumentKind.pdf => <String, dynamic>{
            'action': 'duplicate',
            'page': 0,
          },
        };
        final changed = await backend.editInspected(original, request);
        switch (kind) {
          case NativeDocumentKind.word:
            expect(
              changed.preview['paragraphs'],
              contains('Worker changed 😀'),
            );
          case NativeDocumentKind.grid:
            expect(changed.preview['sheets'][0]['cells']['A1']['input'], '42');
          case NativeDocumentKind.deck:
            expect(
              changed.preview['slides'][0]['shapes'].toString(),
              contains('Worker changed 😀'),
            );
          case NativeDocumentKind.pdf:
            expect(changed.preview['pages'], hasLength(2));
        }
        expect(
          backend.inputTransfers,
          1,
          reason: 'Edit + preview do not resend the output to another isolate',
        );
        expect(await backend.inspect(changed.bytes), changed.preview);
        expect(backend.inputTransfers, 2);
        // A mutable external buffer must never be mistaken for an immutable cached input.
        final mutable = Uint8List.fromList(original);
        expect(await backend.inspect(mutable), before);
        mutable.fillRange(0, mutable.length, 0);
        await expectLater(backend.inspect(mutable), throwsFormatException);
        expect(await backend.inspect(original), before);
        final accepted = backend.inspect(changed.bytes);
        await Future<void>.delayed(Duration.zero);
        await backend.close();
        expect(await accepted, changed.preview);
        await backend.close();
        await expectLater(backend.inspect(original), throwsStateError);
        expect(backend.workerStarts, 1);
        debugPrint(
          'WORKER_LIFECYCLE ${kind.name} starts=${backend.workerStarts} inputTransfers=${backend.inputTransfers} passed',
        );
      }
    },
  );

  testWidgets(
    'Actual Android: PPTX pictures share one worker/input and preserve slide authorization',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.deck);
      addTearDown(backend.close);
      final file = immutableDocumentBytes(workerMediaDeck);
      final report = await backend.inspect(file);
      final shapes = report['slides'][1]['shapes'] as List;
      final media =
          shapes.firstWhere((s) => s['imageId'] is int)['imageId'] as int;
      final pictures = await Future.wait(
        List.generate(3, (_) => backend.image(file, 1, media)),
      );
      for (final picture in pictures) {
        expect(picture, orderedEquals(workerMediaPng));
      }
      await expectLater(backend.image(file, 0, media), throwsFormatException);
      expect(
        await backend.image(file, 1, media),
        orderedEquals(workerMediaPng),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeDeckScreen(
            backend: backend,
            launch: EditorLaunch(bytes: file, name: 'Worker picture.pptx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(backend.workerStarts, 1);
      expect(backend.inputTransfers, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await backend.close();
      debugPrint(
        'WORKER_MEDIA starts=1 inputTransfers=1 exactPNG=verified authorization=verified',
      );
    },
  );
  testWidgets(
    'Actual Android: distant XLSX window edits, pan, history and exported formulas',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      var bytes = await backend.create();
      bytes = await backend.edit(bytes, {
        'sheet': 0,
        'address': 'A1',
        'value': '12',
      });
      bytes = await backend.edit(bytes, {
        'sheet': 0,
        'address': 'AA1000',
        'value': '=A1+30',
      });
      final original = bytes;
      final window = const GridWindow(0, 999, 26, rows: 1, columns: 1).buffered;
      expect(
        (await backend.inspectGrid(
          bytes,
          window,
          'AA1000',
        ))['selection']['display'],
        '42',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeGridScreen(
            backend: backend,
            launch: EditorLaunch(bytes: bytes, name: 'Distant.xlsx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, '15');
      await tester.tap(find.byKey(const Key('tool-section-caption')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вид'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перейти к ячейке'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('grid-address-input')),
        'AA1000',
      );
      await tester.tap(find.text('Перейти'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '=A1+30');
      expect(find.byKey(const ValueKey('grid-cell-AA1000')), findsOneWidget);
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      expect(find.text('45'), findsWidgets);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture(tester, 'grid-window-AA1000');
      await tester.enterText(formula, '=A1*4');
      final viewport = tester.state<SheetViewportState>(
        find.byType(SheetViewport),
      );
      viewport.goToCell(1500, 60);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '=A1*4');
      viewport.goToCell(999, 26);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '=A1*4');
      await tester.tap(find.byTooltip('Применить'));
      await tester.pumpAndSettle();
      expect(find.text('60'), findsWidgets);
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '=A1+30');
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '=A1*4');
      Uint8List? exported;
      const files = MethodChannel('flutter_file_dialog');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            exported = (call.arguments as Map)['data'] as Uint8List;
            return '/test/distant.xlsx';
          });
      try {
        await tester.tap(find.byTooltip('Меню файла'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранить копию'));
        await tester.pumpAndSettle();
        final reread = await backend.inspectGrid(exported!, window, 'AA1000');
        expect(reread['selection']['input'], '=A1*4');
        expect(reread['selection']['display'], '60');
        expect(
          (await backend.inspectGrid(
            original,
            window,
            'AA1000',
          ))['selection']['display'],
          '42',
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null);
      }
      expect(backend.workerStarts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await backend.close();
    },
  );
  testWidgets(
    'Actual Android: imported XLSX geometry, finger resize, undo and saved layout',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      final original = gridLayoutFixture();
      final initial = await backend.inspectGrid(
        original,
        const GridWindow(0, 0, 0),
        'A1',
      );
      final colRun = (initial['layout']['columns'] as List).first as List;
      final oldWidth = (colRun[2] as num).toDouble();
      final oldHeight =
          ((initial['layout']['rows'] as List).firstWhere((v) => v[0] == 3)[2]
                  as num)
              .toDouble();
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeGridScreen(
            backend: backend,
            launch: EditorLaunch(bytes: original, name: 'Imported-layout.xlsx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      final merged = find.byKey(const ValueKey('grid-cell-A1'));
      expect(tester.getSize(merged).width, greaterThan(oldWidth * 2));
      expect(tester.getSize(merged).height, closeTo(68 * 4 / 3, .1));
      expect(find.byKey(const ValueKey('grid-cell-B2')), findsNothing);
      expect(find.byKey(const ValueKey('grid-row-header-2')), findsNothing);
      expect(find.byKey(const ValueKey('grid-column-header-3')), findsNothing);
      await capture(tester, 'imported-grid-layout');
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'Edited merged title');
      // Keep the keyboard out of the document, without applying pending text.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      Future<void> dragHeading(String key, Offset delta) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey(key))),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await gesture.moveBy(delta);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await dragHeading('grid-column-header-0', const Offset(60, 0));
      expect(
        tester
            .state<SheetViewportState>(find.byType(SheetViewport))
            .columns
            .extent(0),
        closeTo(oldWidth + 60, 1),
      );
      expect(
        tester.widget<TextField>(formula).controller!.text,
        'Edited merged title',
      );
      await dragHeading('grid-row-header-3', const Offset(0, -20));
      expect(
        tester
            .state<SheetViewportState>(find.byType(SheetViewport))
            .rows
            .extent(3),
        closeTo(oldHeight - 20, 1),
      );
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<SheetViewportState>(find.byType(SheetViewport))
            .rows
            .extent(3),
        closeTo(oldHeight, 1),
      );
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<SheetViewportState>(find.byType(SheetViewport))
            .rows
            .extent(3),
        closeTo(oldHeight - 20, 1),
      );
      Uint8List? exported;
      const files = MethodChannel('flutter_file_dialog');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            exported = (call.arguments as Map)['data'] as Uint8List;
            return '/test/imported-layout.xlsx';
          });
      try {
        await tester.tap(find.byTooltip('Меню файла'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранить копию'));
        await tester.pumpAndSettle();
        final saved = await backend.inspectGrid(
          exported!,
          const GridWindow(0, 0, 0),
          'B2',
        );
        expect(saved['selection']['address'], 'A1');
        expect(saved['selection']['input'], 'Edited merged title');
        expect(saved['layout']['merges'], initial['layout']['merges']);
        expect(
          (saved['layout']['columns'] as List).first[2],
          closeTo(oldWidth + 60, 1),
        );
        expect(
          (saved['layout']['rows'] as List).firstWhere((v) => v[0] == 3)[2],
          closeTo(oldHeight - 20, 1),
        );
        expect(saved['sheets'][0]['cells']['B4']['display'], '12.50%');
        expect(
          (await backend.inspectGrid(
            original,
            const GridWindow(0, 0, 0),
            'A1',
          ))['selection']['input'],
          'Imported merged title',
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null);
      }
      await capture(tester, 'imported-grid-resized');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await backend.close();
    },
  );
  testWidgets(
    'Compact headings and actual formula commands save, undo and reopen',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(() => backend.close());
      var bytes = await backend.create();
      for (final entry in {'A1': '12', 'A2': '8'}.entries) {
        bytes = await backend.edit(bytes, {
          'sheet': 0,
          'address': entry.key,
          'value': entry.value,
        });
      }
      bytes = await backend.edit(bytes, {
        'sheet': 0,
        'address': 'B1',
        'action': 'format',
        'value': 'Long imported label',
        'style': {'shrink': true},
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeGridScreen(
            backend: backend,
            launch: EditorLaunch(bytes: bytes, name: 'Formulas.xlsx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('grid-column-header-0')))
            .height,
        28,
      );
      final shrink = find.descendant(
        of: find.byKey(const ValueKey('grid-cell-B1')),
        matching: find.byType(FittedBox),
      );
      expect(shrink, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('grid-cell-A3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Формулы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('∑ Автосумма'));
      await tester.pumpAndSettle();
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(formula).controller!.text, '=SUM(A1:A2)');
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '');
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(formula).controller!.text, '=SUM(A1:A2)');
      await tester.tap(find.text('Пересчитать'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      const files = MethodChannel('flutter_file_dialog');
      Uint8List? exported;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            exported = (call.arguments as Map)['data'] as Uint8List;
            return '/test/Formulas.xlsx';
          });
      try {
        await tester.tap(find.byTooltip('Меню файла'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранить копию'));
        await tester.pumpAndSettle();
        final reopened = await backend.inspectGrid(
          exported!,
          const GridWindow(0, 0, 0),
          'A3',
        );
        expect(reopened['selection']['input'], '=SUM(A1:A2)');
        expect(reopened['selection']['display'], '20');
        expect(reopened['sheets'][0]['cells']['B1']['style']['shrink'], true);
        expect(
          (await backend.inspectGrid(
            bytes,
            const GridWindow(0, 0, 0),
            'A3',
          ))['selection']['input'],
          '',
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null);
      }
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture(tester, 'compact-grid-formulas');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Continuous sheet zoom, empty cells, editing and export use real Rust',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(() => backend.close());
      var bytes = gridLayoutFixture();
      bytes = await backend.edit(bytes, {
        'sheet': 0,
        'address': 'K232',
        'value': 'Overview end',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: NativeGridScreen(
            backend: backend,
            launch: EditorLaunch(bytes: bytes, name: 'Overview.xlsx'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.state<SheetViewportState>(
        find.byType(SheetViewport),
      );
      viewport.goToCell(20, 5);
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byKey(const Key('sheet-viewport')));
      final corner = tester.getRect(find.byKey(const ValueKey('grid-corner')));
      expect(corner.right, lessThan(canvas.left));
      expect(corner.bottom, lessThan(canvas.top));
      viewport.goToCell(0, 0);
      await tester.pumpAndSettle();
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'Keep pending zoom input');
      viewport.setZoom(.1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('grid-cells-canvas')), findsOneWidget);
      expect(viewport.screenPoint(Offset.zero), const Offset(46, 28));
      final layout = (await backend.inspectGrid(
        bytes,
        const GridWindow(0, 0, 0),
        'A1',
      ))['layout'];
      final gridLayout = GridLayout.fromJson(layout as Map);
      viewport.goToCell(200, 2);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byKey(const Key('sheet-viewport')));
      await tester.tapAt(
        origin +
            viewport.screenPoint(
              Offset(
                gridLayout.columns.offset(2) + gridLayout.columns.extent(2) / 2,
                gridLayout.rows.offset(200) + gridLayout.rows.extent(200) / 2,
              ),
            ),
      );
      await tester.pumpAndSettle();
      expect(viewport.zoom, .1);
      for (var tries = 0; tries < 100; tries++) {
        if (!tester.widget<TextField>(formula).readOnly &&
            find.text('C201').evaluate().isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.widget<TextField>(formula).readOnly, false);
      expect(find.text('C201'), findsOneWidget);
      await tester.tap(formula);
      await tester.pumpAndSettle();
      await tester.enterText(formula, 'Edited at reduced zoom');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Применить'));
      await tester.pumpAndSettle();
      const files = MethodChannel('flutter_file_dialog');
      Uint8List? exported;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            exported = (call.arguments as Map)['data'] as Uint8List;
            return '/test/Overview.xlsx';
          });
      try {
        await tester.tap(find.byTooltip('Меню файла'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Сохранить копию'));
        await tester.pumpAndSettle();
        final selected = await backend.inspectGrid(
          exported!,
          const GridWindow(0, 200, 2),
          'C201',
        );
        expect(selected['selection']['input'], 'Edited at reduced zoom');
        expect(
          (await backend.inspectGrid(
            exported!,
            const GridWindow(0, 0, 0),
            'A1',
          ))['selection']['input'],
          'Keep pending zoom input',
        );
        expect(
          (await backend.inspectGrid(
            bytes,
            const GridWindow(0, 0, 0),
            'A1',
          ))['selection']['input'],
          'Imported merged title',
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null);
      }
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture(tester, 'continuous-zoom-edited-cell');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
