import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/gridcraft_bridge.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/platform/application_storage.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/ui/page_reading.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'grid_layout_fixture.dart';
import 'worker_media_fixture.dart';
import 'word_navigation_fixture.dart';

Uint8List pdfTextFixture({int secondPageHeight = 842}) {
  const stream =
      'BT /F1 18 Tf 40 760 Td (Original title for this page) Tj ET\n'
      'BT /F1 12 Tf 40 650 Td (Keep this line) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 595 842] >>',
    '<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 $secondPageHeight] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
  ];
  return pdfObjects(objects.map(ascii.encode).toList());
}

Uint8List pdfObjects(List<List<int>> objects) {
  final pdf = BytesBuilder();
  void append(String text) => pdf.add(ascii.encode(text));
  append('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (index, object) in objects.indexed) {
    offsets.add(pdf.length);
    append('${index + 1} 0 obj\n');
    pdf.add(object);
    append('\nendobj\n');
  }
  final xref = pdf.length;
  append('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    append('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  append(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return pdf.takeBytes();
}

Future<Uint8List> scanFixture() async {
  const width = 1000, height = 440;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  final painter = TextPainter(
    text: const TextSpan(
      text: 'ПРОВЕРКА ТЕКСТА\nOFFLINE TEST',
      style: TextStyle(fontFamily: 'Roboto', fontSize: 64, color: Colors.black),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, const Offset(60, 100));
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = (await image.toByteData())!;
  final pixels = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  image.dispose();
  final rgb = Uint8List(width * height * 3);
  for (var i = 0, j = 0; i < pixels.length; i += 4, j += 3) {
    rgb[j] = pixels[i];
    rgb[j + 1] = pixels[i + 1];
    rgb[j + 2] = pixels[i + 2];
  }
  final compressed = zlib.encode(rgb);
  const commands = 'q 600 0 0 264 0 0 cm /Scan Do Q\n';
  return pdfObjects([
    ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 264] '
      '/Resources << /XObject << /Scan 4 0 R >> >> /Contents 5 0 R >>',
    ),
    [
      ...ascii.encode(
        '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode '
        '/Length ${compressed.length} >>\nstream\n',
      ),
      ...compressed,
      ...ascii.encode('\nendstream'),
    ],
    ascii.encode(
      '<< /Length ${commands.length} >>\nstream\n${commands}endstream',
    ),
  ]);
}

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
    'XLSX reader reuses snapshots, replaces edits and frees worker sessions',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(backend.close);
      final original = immutableDocumentBytes(gridLayoutFixture());
      const window = GridWindow(0, 0, 0, rows: 6, columns: 6);
      final before = await backend.inspectGrid(original, window, 'A1');
      for (var i = 0; i < 4; i++) {
        expect(await backend.inspectGrid(original, window, 'A1'), before);
      }
      expect(backend.inputTransfers, 1);
      final changed = await backend.editAndInspectGrid(
        original,
        {'sheet': 0, 'address': 'A1', 'value': 'New snapshot'},
        window,
        'A1',
      );
      expect(changed.preview['selection']['input'], 'New snapshot');
      expect(
        (await backend.inspectGrid(
          changed.bytes,
          window,
          'A1',
        ))['selection']['input'],
        'New snapshot',
      );
      expect(
        (await backend.inspectGrid(
          original,
          window,
          'A1',
        ))['selection']['input'],
        before['selection']['input'],
      );
      await backend.close();
      // Two low-level readers fit only if the worker released its model on close.
      final bridge = GridCraftBridge.tryOpen()!;
      final first = bridge.openReader(original)!;
      addTearDown(() => bridge.closeReader(first));
      final second = bridge.openReader(original)!;
      addTearDown(() => bridge.closeReader(second));
      final fallback = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(fallback.close);
      expect(await fallback.inspectGrid(original, window, 'A1'), before);
      await fallback.close();
      bridge.closeReader(first);
      bridge.closeReader(second);
      final reopened = NativeDocumentBackend(NativeDocumentKind.grid);
      addTearDown(reopened.close);
      expect(await reopened.inspectGrid(original, window, 'A1'), before);
      await reopened.close();
    },
  );

  testWidgets(
    'Android legacy reading preferences survive and new Dart files take precedence',
    (tester) async {
      // tools/ci/run_android_checks.py seeds these old-format XML preferences.
      final storage = AndroidApplicationStorage();
      expect(await storage.readReadingMode('pdf'), 'continuous');
      expect(await storage.readReadingMode('deck'), 'vertical');
      await Future.wait([
        storage.writeReadingMode('pdf', 'vertical'),
        AndroidApplicationStorage().writeReadingMode('deck', 'horizontal'),
      ]);
      final reopened = AndroidApplicationStorage();
      expect(await reopened.readReadingMode('pdf'), 'vertical');
      expect(await reopened.readReadingMode('deck'), 'horizontal');
      final root = await storage.workspaceDirectory();
      expect(
        jsonDecode(await File('${root.path}/reading-pdf.json').readAsString()),
        {'mode': 'vertical'},
      );
      const legacy = MethodChannel('artofficecraft/reading');
      expect(
        await legacy.invokeMethod<String>('read', {'format': 'pdf'}),
        'continuous',
      );
      expect(
        await legacy.invokeMethod<String>('read', {'format': 'deck'}),
        'vertical',
      );
      await storage.writeReadingMode('pdf', 'horizontal');
    },
  );

  testWidgets(
    'Word long-document navigation keeps drafts and follows imported headings',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.word);
      addTearDown(backend.close);
      final original = wordNavigationFixture();
      final imported = await backend.inspect(original);
      final blocks = imported['blocks'] as List;
      expect(blocks.length, 2000);
      expect(
        blocks
            .where((b) => b['outlineLevel'] != null)
            .map((b) => b['outlineLevel']),
        [0, 1, 2],
      );
      expect(
        blocks.last['block'],
        2000,
      ); // A table is not a body-text paragraph.
      await present(
        tester,
        NativeWordScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Long.docx'),
        ),
      );
      await tester.tap(find.text('Первый раздел'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        'Первый раздел изменён',
      );
      await tool(tester, 'Вид', 'Навигация');
      await tester.enterText(
        find.byKey(const Key('word-heading-filter')),
        'последний',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Последний раздел 😀'));
      await tester.tap(find.text('Последний раздел 😀'));
      await until(
        tester,
        () =>
            panel(tester).undo != null &&
            find
                .byKey(const ValueKey(('word-paragraph', 2000)))
                .evaluate()
                .isNotEmpty,
        'far heading and draft commit',
      );
      expect(find.byKey(const Key('word-inline-input')), findsNothing);
      expect(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey &&
                  switch ((w.key as ValueKey).value) {
                    ('word-paragraph', int _) => true,
                    _ => false,
                  },
            )
            .evaluate()
            .length,
        lessThan(20),
      );
      final exported = await save(tester, 'Сохранить как DOCX');
      final reopened = await backend.inspect(exported);
      expect((reopened['paragraphs'] as List).first, 'Первый раздел изменён');
      expect((reopened['paragraphs'] as List).last, 'Последний раздел 😀');
      await tool(tester, 'Вид', 'Навигация');
      await tester.enterText(find.byKey(const Key('word-jump-number')), '1000');
      await tester.ensureVisible(find.byTooltip('Перейти к абзацу'));
      await tester.tap(find.byTooltip('Перейти к абзацу'));
      await until(
        tester,
        () => find
            .byKey(const ValueKey(('word-paragraph', 1000)))
            .evaluate()
            .isNotEmpty,
        'paragraph navigation across table block',
      );
      expect(find.text('Средний раздел'), findsOneWidget);
      await tool(tester, 'Вид', 'Навигация');
      await capture(tester, 'word-long-navigation-045');
      await tester.ensureVisible(find.byKey(const Key('word-heading-list')));
      await capture(tester, 'word-heading-list-045');
      await tester.ensureVisible(find.byTooltip('Очистить поиск'));
      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(('word-heading', 0))), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('word-heading-list')));
      await capture(tester, 'word-heading-cleared-045');
      await press(tester, 'В начало документа');
      await until(
        tester,
        () => find.text('Первый раздел изменён').evaluate().isNotEmpty,
        'start',
      );
      await history(tester, true);
      expect(
        (await backend.inspect(
          await save(tester, 'Сохранить как DOCX'),
        ))['paragraphs'],
        contains('Первый раздел'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
    'PPTX touch gestures move text and pictures and resize a picture on export',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.deck);
      addTearDown(backend.close);
      final original = workerMediaDeck;
      final initial = await backend.inspect(original);
      Map shape(Map summary, int slide, bool picture) =>
          (summary['slides'][slide]['shapes'] as List).cast<Map>().firstWhere(
            (s) => picture ? s['imageId'] != null : s['editableText'] == true,
          );
      final text = shape(initial, 1, false);
      final picture = shape(initial, 1, true);
      await present(
        tester,
        NativeDeckScreen(
          backend: backend,
          launch: EditorLaunch(bytes: original, name: 'Touch.pptx'),
        ),
      );
      await readingMode(tester, 'Вид', 'По одной, горизонтально');
      await tool(tester, 'Вид', 'Перейти к слайду');
      await tester.enterText(find.byKey(const Key('reader-jump-number')), '2');
      await press(tester, 'Перейти к слайду');
      await collapse(tester);
      await tester.tap(find.byKey(const Key('deck-object-editing')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(ValueKey("deck-object-1-${text['id']}")),
        const Offset(40, 36),
      );
      await until(tester, () => panel(tester).undo != null, 'text moved');
      final moved = await save(tester, 'Сохранить копию PPTX');
      final movedText = shape(await backend.inspect(moved), 1, false);
      expect(movedText['rect']['x'] as num, greaterThan(text['rect']['x']));
      expect(movedText['rect']['y'] as num, greaterThan(text['rect']['y']));
      expect(movedText['text'], text['text']);
      final pictureView = find.byKey(
        ValueKey("deck-object-1-${picture['id']}"),
      );
      await tester.drag(pictureView, const Offset(-44, 0));
      await tester.pumpAndSettle();
      final movedPicture = shape(
        await backend.inspect(await save(tester, 'Сохранить копию PPTX')),
        1,
        true,
      );
      expect(movedPicture['rect']['x'] as num, lessThan(picture['rect']['x']));
      final handle = find.byKey(const Key('deck-object-resize'));
      expect(handle, findsOneWidget);
      await capture(tester, 'deck-object-030');
      await tester.drag(handle, const Offset(32, 26));
      await tester.pumpAndSettle();
      final resized = await save(tester, 'Сохранить копию PPTX');
      final after = shape(await backend.inspect(resized), 1, true);
      expect(after['rect']['w'] as num, greaterThan(picture['rect']['w']));
      expect(
        await backend.image(resized, 1, after['imageId'] as int),
        workerMediaPng,
      );
      await history(tester, true);
      final undo = await save(tester, 'Сохранить копию PPTX');
      expect(
        shape(await backend.inspect(undo), 1, true)['rect'],
        movedPicture['rect'],
      );
    },
  );

  testWidgets('PDF text notes persist with Unicode and are restored by redo', (
    tester,
  ) async {
    final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
    addTearDown(backend.close);
    await present(
      tester,
      NativePdfScreen(
        backend: backend,
        launch: EditorLaunch(bytes: await backend.create(), name: 'Notes.pdf'),
      ),
    );
    await tool(tester, 'Комментарии', 'Комментарий');
    const note = 'Заметка для проверки ✓';
    await tester.enterText(find.byKey(const Key('pdf-note-text')), note);
    await tester.pumpAndSettle();
    await press(tester, 'Добавить заметку');
    await until(tester, () => panel(tester).undo != null, 'note added');
    final saved = await save(tester, 'Сохранить PDF');
    expect((await backend.inspect(saved))['notes'], [
      {'page': 0, 'text': note},
    ]);
    await history(tester, true);
    expect(
      (await backend.inspect(await save(tester, 'Сохранить PDF')))['notes'],
      isEmpty,
    );
    await history(tester, false);
    await tool(tester, 'Комментарии', 'Все комментарии');
    expect(find.text(note), findsOneWidget);
    await capture(tester, 'pdf-note-030');
  });

  testWidgets('PDF page text is rewritten, preserved on export and undoable', (
    tester,
  ) async {
    final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
    addTearDown(backend.close);
    final original = pdfTextFixture();
    const title = 'Original title for this page';
    const keep = 'Keep this line';
    const replacement = 'Новый заголовок';
    final firstPage = await backend.pdfTextBlocks(original, 0);
    expect(firstPage.blocks.map((block) => block.text), [title, keep]);
    expect((await backend.pdfTextBlocks(original, 1)).blocks, isEmpty);
    await expectLater(
      backend.edit(original, {
        'action': 'replace_text_block',
        'page': 0,
        'block': firstPage.blocks.first.id,
        'original': 'Stale text',
        'text': replacement,
      }),
      throwsA(anything),
    );
    await present(
      tester,
      NativePdfScreen(
        backend: backend,
        launch: EditorLaunch(bytes: original, name: 'Page text.pdf'),
      ),
    );
    await tool(tester, 'Изменить', 'Текст PDF');
    await until(tester, () => find.text(title).evaluate().isNotEmpty, 'blocks');
    await press(tester, title);
    final input = find.byKey(const Key('pdf-page-text-input'));
    expect(tester.widget<TextField>(input).controller!.text, title);
    await tester.enterText(input, replacement);
    await tester.pumpAndSettle();
    await press(tester, 'Применить правку текста');
    await until(tester, () => panel(tester).undo != null, 'PDF text edited');
    final saved = await save(tester, 'Сохранить PDF');
    final editedBlocks = (await backend.pdfTextBlocks(saved, 0)).blocks;
    expect(editedBlocks.map((block) => block.text), [replacement, keep]);
    expect((await backend.inspect(saved))['pageCount'], 2);
    await history(tester, true);
    final undo = await save(tester, 'Сохранить PDF');
    expect((await backend.pdfTextBlocks(undo, 0)).blocks, firstPage.blocks);
    await history(tester, false);
    await tool(tester, 'Изменить', 'Текст PDF');
    await until(
      tester,
      () => find.text(replacement).evaluate().isNotEmpty,
      'updated blocks',
    );
    await capture(tester, 'pdf-page-text-031');
  });

  testWidgets('PDF touch inserts searchable text on a zoomed rotated page', (
    tester,
  ) async {
    final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
    addTearDown(backend.close);
    final original = await backend.edit(pdfTextFixture(), {
      'action': 'rotate_cw',
      'page': 0,
    });
    await present(
      tester,
      NativePdfScreen(
        backend: backend,
        launch: EditorLaunch(bytes: original, name: 'Insert text.pdf'),
      ),
    );
    await readingMode(tester, 'Чтение', 'По одной, горизонтально');
    await tool(tester, 'Изменить', 'Вставить текст');
    const text = 'Текст в выбранном месте';
    final input = find.byKey(const Key('pdf-insert-text-input'));
    final canvas = find.byKey(const Key('pdf-page-canvas'));
    await tester.enterText(input, text);
    await tester.pumpAndSettle();
    await press(tester, 'Выбрать место');
    await tester.pumpAndSettle();
    expect(
      find.text('Коснитесь страницы, чтобы вставить текст'),
      findsOneWidget,
    );
    final initial = tester.getRect(canvas);
    await tester.tapAt(Offset(initial.right - .5, initial.center.dy));
    await until(
      tester,
      () => input.evaluate().isNotEmpty,
      'placement rejected',
    );
    expect(tester.widget<TextField>(input).controller!.text, text);
    expect(panel(tester).undo, isNull);

    await press(tester, 'Выбрать место');
    await tester.pumpAndSettle();
    final center = tester.getCenter(canvas);
    final viewport = tester.state<PdfViewportState>(find.byType(PdfViewport));
    final initialScale = viewport.transform.value.getMaxScaleOnAxis();
    final a = await tester.createGesture(pointer: 1);
    final b = await tester.createGesture(pointer: 2);
    await a.down(center - const Offset(24, 0));
    await b.down(center + const Offset(24, 0));
    await tester.pump();
    for (var step = 1; step <= 4; step++) {
      final distance = 24.0 + step * 8;
      await a.moveTo(center - Offset(distance, 0));
      await b.moveTo(center + Offset(distance, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    final zoom = viewport.transform.value.getMaxScaleOnAxis();
    expect(zoom, greaterThan(initialScale));
    expect(panel(tester).undo, isNull);

    final page = tester.getRect(canvas);
    await tester.tapAt(
      page.topLeft + Offset(page.width * .4, page.height * .55),
    );
    await until(tester, () => panel(tester).undo != null, 'text inserted');
    final saved = await save(tester, 'Сохранить PDF');
    final blocks = (await backend.pdfTextBlocks(saved, 0)).blocks;
    expect(
      blocks.map((block) => block.text),
      containsAll([text, 'Original title for this page', 'Keep this line']),
    );
    expect((await backend.inspect(saved))['pages'][0]['rotation'], 90);
    expect(viewport.transform.value.getMaxScaleOnAxis(), closeTo(zoom, .001));
    await capture(tester, 'pdf-insert-text-032');
    await history(tester, true);
    final undo = await save(tester, 'Сохранить PDF');
    expect(
      (await backend.pdfTextBlocks(undo, 0)).blocks.map((block) => block.text),
      isNot(contains(text)),
    );
    await history(tester, false);
    final redo = await save(tester, 'Сохранить PDF');
    expect(
      (await backend.pdfTextBlocks(redo, 0)).blocks.map((block) => block.text),
      contains(text),
    );
  });

  testWidgets('PDF search highlights matches and follows both reading modes', (
    tester,
  ) async {
    final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
    addTearDown(backend.close);
    final rotated = await backend.edit(pdfTextFixture(secondPageHeight: 1800), {
      'action': 'rotate_cw',
      'page': 0,
    });
    final original = await backend.edit(rotated, {
      'action': 'insert_text',
      'page': 1,
      'text': 'This is on page two',
      'x': .15,
      'y': .82,
      'size': 18,
    });
    await present(
      tester,
      NativePdfScreen(
        backend: backend,
        launch: EditorLaunch(bytes: original, name: 'Search.pdf'),
      ),
    );
    await readingMode(tester, 'Чтение', 'По одной, горизонтально');
    await tool(tester, 'Чтение', 'Поиск');
    await tester.enterText(find.byKey(const Key('pdf-find-input')), 'THIS');
    await tester.pumpAndSettle();
    await press(tester, 'Найти в PDF');
    final highlight = find.byKey(const Key('pdf-search-highlight'));
    await until(
      tester,
      () => highlight.evaluate().isNotEmpty,
      'first PDF match',
    );
    expect(find.text('Результат 1 из 3'), findsOneWidget);
    expect(
      tester.widget<PdfViewport>(find.byType(PdfViewport)).highlight,
      isNotNull,
    );

    await tester.tap(find.byTooltip('Предыдущее совпадение'));
    await until(tester, () => highlight.evaluate().isNotEmpty, 'wrapped match');
    expect(find.text('Результат 3 из 3'), findsOneWidget);
    expect(find.text('Страница 2 из 2'), findsOneWidget);
    final view = tester.state<PdfViewportState>(find.byType(PdfViewport));
    expect(view.transform.value.getTranslation().y, lessThan(0));

    await readingMode(tester, 'Чтение', 'Непрерывно вниз');
    await collapse(tester);
    await until(tester, () => highlight.evaluate().isNotEmpty, 'strip match');
    expect(
      tester.widget<ContinuousPages>(find.byType(ContinuousPages)).page,
      1,
    );
    await tester.tap(find.byTooltip('Следующее совпадение'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ContinuousPages>(find.byType(ContinuousPages)).page,
      0,
    );
    expect(find.text('Результат 1 из 3'), findsOneWidget);
    await capture(tester, 'pdf-find-036');
    await tester.tap(find.byTooltip('Закрыть поиск'));
    await tester.pumpAndSettle();
    expect(highlight, findsNothing);
    expect(panel(tester).undo, isNull);
  });

  testWidgets(
    'Offline OCR copies and saves searchable text over the same image',
    (tester) async {
      final backend = NativeDocumentBackend(NativeDocumentKind.pdf);
      addTearDown(backend.close);
      final bytes = await scanFixture();
      expect((await backend.pdfTextBlocks(bytes, 0)).blocks, isEmpty);
      await present(
        tester,
        NativePdfScreen(
          backend: backend,
          launch: EditorLaunch(bytes: bytes, name: 'Scan.pdf'),
        ),
      );
      await readingMode(tester, 'Чтение', 'По одной, горизонтально');
      final raster = find.descendant(
        of: find.byKey(const Key('pdf-page-canvas')),
        matching: find.byType(Image),
      );
      await until(
        tester,
        () => raster.evaluate().isNotEmpty,
        'original raster',
      );
      final originalImage =
          (tester.widget<Image>(raster).image as MemoryImage).bytes;
      await tool(tester, 'Изменить', 'Скан и OCR');
      await press(tester, 'Распознать страницу');
      final output = find.byKey(const Key('pdf-ocr-result'));
      await until(tester, () => output.evaluate().isNotEmpty, 'OCR text');
      final text = tester.widget<SelectableText>(output).data!;
      expect(text, contains('ПРОВЕРКА ТЕКСТА'));
      expect(text, contains('OFFLINE TEST'));
      expect(panel(tester).undo, isNull);
      await capture(tester, 'pdf-ocr-033');
      await press(tester, 'Скопировать распознанный текст');
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
      await press(tester, 'Добавить текстовый слой');
      await until(
        tester,
        () => panel(tester).undo != null,
        'OCR layer applied',
      );
      await until(
        tester,
        () => raster.evaluate().isNotEmpty,
        'raster with OCR',
      );
      final after = (tester.widget<Image>(raster).image as MemoryImage).bytes;
      expect(after, originalImage);
      final saved = await save(tester, 'Сохранить PDF');
      expect(saved, isNot(equals(bytes)));
      expect((await backend.pdfTextBlocks(saved, 0)).blocks, isEmpty);
      for (final query in ['проверка текста', 'offline test']) {
        final found = await backend.pdfFind(saved, query, 0, 512);
        expect(found.hits.single.page, 0);
        expect(found.incomplete, isFalse);
      }

      await expectLater(
        backend.edit(saved, {
          'action': 'add_ocr_layer',
          'page': 0,
          'words': [
            {
              'text': 'Duplicate',
              'rect': [.1, .1, .2, .2],
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'This PDF page already contains searchable text',
          ),
        ),
      );
      await history(tester, true);
      expect(await save(tester, 'Сохранить PDF'), bytes);
      await history(tester, false);
      expect(await save(tester, 'Сохранить PDF'), saved);
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
