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
      await tester.pumpWidget(const ArtOfficeCraftApp());
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture(tester, 'home');
      final word = NativeDocumentBackend.tryOpen(NativeDocumentKind.word)!;
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
      expect(info['coreVersion'], '0.13.0');
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
}
