import 'package:artofficecraft_mobile/ui/editor_tools.dart';

import 'dart:convert';
import 'dart:async';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDocumentBackend implements DocumentBackend {
  FakeDocumentBackend(this.kind);
  final NativeDocumentKind kind;
  String text = 'Проверяемый абзац';
  final Map<String, dynamic> cells = {};
  int calls = 0;
  bool failEdits = false;
  Map<String, dynamic>? lastEdit;
  Uint8List bytes() => Uint8List.fromList(utf8.encode('%PDF-$text'));
  @override
  Future<Uint8List> create([String value = '']) async => bytes();
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async => switch (kind) {
    NativeDocumentKind.word => {
      'paragraphs': [text],
      'tables': 0,
      'blocks': [
        {
          'block': 0,
          'text': text,
          'editable': true,
          'align': 'justify',
          'runs': [
            {'text': text},
          ],
        },
      ],
    },
    NativeDocumentKind.grid => {
      'sheets': [
        {'name': 'Лист 1', 'cells': cells},
      ],
    },
    NativeDocumentKind.deck => {
      'width': 960,
      'height': 540,
      'slides': [
        {
          'shapes': [
            {
              'id': 1,
              'text': text,
              'editableText': true,
              'rect': {'x': 20, 'y': 20, 'w': 600, 'h': 100},
            },
          ],
        },
      ],
    },
    NativeDocumentKind.pdf => {
      'pages': [
        {'width': 595, 'height': 842, 'rotation': 0},
      ],
    },
  };
  @override
  Future<Uint8List> edit(Uint8List old, Map<String, dynamic> request) async {
    calls++;
    lastEdit = request;
    if (failEdits) throw StateError("Intentional native failure");
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (request['address'] != null) {
      cells[request['address']] = {
        'input': request['value'],
        'display': request['value'],
      };
    }
    if (request['text'] != null) text = request['text'] as String;
    return bytes();
  }
}

Future<void> setup(
  WidgetTester tester,
  Size size,
  double scale,
  Widget screen, {
  EdgeInsets insets = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: OfficeTheme.build(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
          viewInsets: insets,
        ),
        child: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(393, 873), const Size(800, 360)]) {
    testWidgets('Inline Word with keyboard and 160 percent text at $size', (
      tester,
    ) async {
      final backend = FakeDocumentBackend(NativeDocumentKind.word);
      await setup(
        tester,
        size,
        1.6,
        NativeWordScreen(
          backend: backend,
          launch: const EditorLaunch(create: true),
        ),
        insets: EdgeInsets.only(bottom: size.height < 500 ? 150 : 300),
      );
      await tester.tap(find.text('Проверяемый абзац'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        'Текст с клавиатурой',
      );
      await tester.pump();
      expect(find.byKey(const Key('tool-section-caption')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final kind in [
      NativeDocumentKind.word,
      NativeDocumentKind.grid,
      NativeDocumentKind.deck,
    ]) {
      testWidgets('Loaded $kind at $size and large text does not overflow', (
        tester,
      ) async {
        final backend = FakeDocumentBackend(kind);
        final screen = switch (kind) {
          NativeDocumentKind.word => NativeWordScreen(
            backend: backend,
            launch: const EditorLaunch(create: true),
          ),
          NativeDocumentKind.grid => NativeGridScreen(
            backend: backend,
            launch: const EditorLaunch(create: true),
          ),
          _ => NativeDeckScreen(
            backend: backend,
            launch: const EditorLaunch(create: true),
          ),
        };
        await setup(tester, size, 1.6, screen);
        expect(tester.takeException(), isNull);
        expect(find.text('Главная'), findsOneWidget);
        expect(find.byTooltip('Меню файла'), findsOneWidget);
      });
    }
  }
  testWidgets('Word applies the paragraph editing result', (tester) async {
    final backend = FakeDocumentBackend(NativeDocumentKind.word);
    await setup(
      tester,
      const Size(393, 873),
      1,
      NativeWordScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    );
    await tester.tap(find.text('Проверяемый абзац'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('word-inline-input')),
      'Отредактированный текст',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Развернуть инструменты'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Готово'));
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(backend.text, 'Отредактированный текст');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Grid ignores cell changes while a commit is pending', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(NativeDocumentKind.grid);
    await setup(
      tester,
      const Size(393, 873),
      1,
      NativeGridScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('grid-cell-A1')));
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.byTooltip('Применить'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('grid-cell-B1')));
    await tester.pumpAndSettle();
    expect(backend.cells['A1']['display'], '123');
    expect(backend.cells.containsKey('B1'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'PPTX text objects are reachable without tapping small slide text',
    (tester) async {
      final backend = FakeDocumentBackend(NativeDocumentKind.deck);
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativeDeckScreen(
          backend: backend,
          launch: const EditorLaunch(create: true),
        ),
      );
      await tester.tap(find.byTooltip('Развернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Текстовые объекты'));
      await tester.tap(find.text('Текстовые объекты'));
      await tester.pumpAndSettle();
      expect(find.text('Проверяемый абзац'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Word typing stays local and Save As flushes the current paragraph',
    (tester) async {
      final backend = FakeDocumentBackend(NativeDocumentKind.word);
      Uint8List? exported;
      const files = MethodChannel('flutter_file_dialog');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, (call) async {
            expect(call.method, 'saveFile');
            exported = (call.arguments as Map)['data'] as Uint8List;
            return '/test/saved.docx';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, null),
      );
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativeWordScreen(
          backend: backend,
          launch: const EditorLaunch(create: true),
        ),
      );
      await tester.tap(find.text('Проверяемый абзац'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.enterText(
        find.byKey(const Key('word-inline-input')),
        'Черновик 😀 без отдельного окна',
      );
      await tester.pump();
      expect(backend.calls, 0);
      await tester.tap(find.byTooltip('Меню файла'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить как DOCX'));
      await tester.pumpAndSettle();
      expect(backend.calls, 1);
      expect(
        utf8.decode(exported!),
        contains('Черновик 😀 без отдельного окна'),
      );
      expect(find.byKey(const Key('word-inline-input')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Word draft survives tools, formatting, collapse and file menu', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(NativeDocumentKind.word);
    Uint8List? exported;
    const files = MethodChannel('flutter_file_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(files, (call) async {
          exported = (call.arguments as Map)['data'] as Uint8List;
          return '/test/saved.docx';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, null),
    );
    await setup(
      tester,
      const Size(393, 873),
      1,
      NativeWordScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    );
    await tester.tap(find.text('Проверяемый абзац'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Развернуть инструменты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Курсив'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('word-inline-input')),
      'Новый текст после оформления 😀',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Свернуть инструменты'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('word-inline-input')))
          .controller!
          .text,
      'Новый текст после оформления 😀',
    );
    await tester.tap(find.byTooltip('Меню файла'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить как DOCX'));
    await tester.pumpAndSettle();
    expect(utf8.decode(exported!), contains('Новый текст после оформления 😀'));
  });

  testWidgets('Failed Word navigation keeps the typed draft and its editor', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(NativeDocumentKind.word);
    await setup(
      tester,
      const Size(393, 873),
      1.6,
      NativeWordScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    );
    await tester.tap(find.text('Проверяемый абзац'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('word-inline-input')),
      'Несохранённый текст 😀',
    );
    backend.failEdits = true;
    await tester.tap(find.byTooltip('Развернуть инструменты'));
    await tester.pumpAndSettle();
    final state = tester.state<EditorToolPanelState>(
      find.byType(EditorToolPanel),
    );
    final view = state.widget.sections.indexWhere((s) => s.label == 'Вид');
    final nav = state.widget.sections[view].tools.indexWhere(
      (t) => t.label == 'Навигация',
    );
    state.openTool(view, [nav]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('word-jump-end')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('word-inline-input')))
          .controller!
          .text,
      'Несохранённый текст 😀',
    );
    expect(state.expanded, isTrue);
    expect(backend.text, 'Проверяемый абзац');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Word retains a failed draft and never exports stale bytes', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(NativeDocumentKind.word)
      ..failEdits = true;
    var exports = 0;
    const files = MethodChannel('flutter_file_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(files, (call) async {
          exports++;
          return '/test/saved.docx';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(files, null),
    );
    await setup(
      tester,
      const Size(393, 873),
      1,
      NativeWordScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    );
    await tester.tap(find.text('Проверяемый абзац'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('word-inline-input')),
      'Не терять этот текст',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Меню файла'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить как DOCX'));
    await tester.pumpAndSettle();
    expect(exports, 0);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('word-inline-input')))
          .controller!
          .text,
      'Не терять этот текст',
    );
    backend.failEdits = false;
    await tester.tap(find.byTooltip('Меню файла'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить как DOCX'));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Repeated Save commands open only one export operation', (
    tester,
  ) async {
    final backend = FakeDocumentBackend(NativeDocumentKind.word);
    final completed = Completer<String?>();
    var exports = 0;
    const channel = MethodChannel('flutter_file_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          exports++;
          return completed.future;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await setup(
      tester,
      const Size(393, 873),
      1,
      NativeWordScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    );
    final action = tester
        .widget<EditorFileMenu>(find.byType(EditorFileMenu))
        .commands
        .firstWhere((c) => c.label == 'Сохранить как DOCX')
        .onPressed!;
    action();
    action();
    await tester.pump();
    expect(exports, 1);
    completed.complete('/test/saved.docx');
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(tester.takeException(), isNull);
  });
}
