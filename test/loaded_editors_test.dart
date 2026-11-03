import 'dart:convert';

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
  Widget screen,
) async {
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
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
      find.byKey(const Key('word-paragraph-input')),
      'Отредактированный текст',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Применить к документу'));
    await tester.tap(find.text('Применить к документу'));
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
      await tester.tap(find.text('Текстовые объекты'));
      await tester.pumpAndSettle();
      expect(find.text('Проверяемый абзац'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}