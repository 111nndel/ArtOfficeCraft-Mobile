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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Actual Android Rust engines: create, edit, reopen, native views',
    (tester) async {
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
      await tester.ensureVisible(find.text('Курсив'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Курсив'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('word-inline-input')), findsOneWidget);
      const finalText = 'Проверка клавиатуры Android 😀 сохранено';
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        finalText,
      );
      await tester.pump();
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
        await tester.tap(find.byTooltip('Сохранить как DOCX'));
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
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Отменить'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Проверка клавиатуры Android'), findsWidgets);
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Повторить'),
        ),
      );
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
      expect(find.text('20'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('grid-cell-A1')));
      await tester.enterText(find.byType(TextField), '15');
      await tester.tap(find.byTooltip('Применить'));
      await tester.pumpAndSettle();
      expect(find.text('23'), findsWidgets);
      expect(tester.takeException(), isNull);

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
      expect(tester.takeException(), isNull);

      final info = await readNativeBuildInfo();
      expect(info!['abi'], 1);
      expect(info['coreVersion'], '0.10.0');
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
