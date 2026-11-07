import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/ui/page_reading.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show setup;
import 'mobile_viewports_test.dart' show pinch, pixel;
import 'office_features_backend.dart';
import 'office_features_test.dart' show press, tool;

Future<void> changeMode(
  WidgetTester tester,
  String section,
  ReadingMode mode,
) async {
  await tool(tester, section, 'Режим чтения');
  await press(tester, mode.label);
  await tester.tap(find.byTooltip('Свернуть инструменты'));
  await tester.pumpAndSettle();
}

void main() {
  const preferenceChannel = MethodChannel('artofficecraft/reading');
  const rendererChannel = MethodChannel('artofficecraft/pdf_renderer');
  final preferences = <String, String>{};
  final renders = <int>[];
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    preferences.clear();
    renders.clear();
    messenger.setMockMethodCallHandler(preferenceChannel, (call) async {
      final args = call.arguments as Map;
      final format = args['format'] as String;
      if (call.method == 'read') return preferences[format];
      preferences[format] = args['mode'] as String;
      return null;
    });
    var session = 0;
    messenger.setMockMethodCallHandler(rendererChannel, (call) async {
      if (call.method == 'openDocument') {
        return {'session': ++session, 'pageCount': 40};
      }
      if (call.method == 'renderPage') {
        final args = call.arguments as Map;
        renders.add(args['page'] as int);
        return pixel;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(preferenceChannel, null);
    messenger.setMockMethodCallHandler(rendererChannel, null);
  });

  testWidgets('PDF searches the outline and jumps by bookmark or number', (
    tester,
  ) async {
    final backend = FeaturesBackend({
      'pages': [
        for (var i = 0; i < 40; i++)
          {'width': 595, 'height': 842, 'rotation': 0},
      ],
      'bookmarks': [
        {'title': 'Введение', 'page': 1, 'depth': 0},
        {'title': 'Приложение', 'page': 37, 'depth': 1},
        {'title': 'Без перехода', 'page': null, 'depth': 0},
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
    await changeMode(tester, 'Чтение', ReadingMode.continuous);
    await tool(tester, 'Чтение', 'Оглавление');
    await tester.enterText(
      find.byKey(const Key('pdf-bookmark-search')),
      'ПРИЛОЖ',
    );
    await tester.pumpAndSettle();
    expect(find.text('Введение'), findsNothing);
    await press(tester, 'Приложение');
    await tester.pumpAndSettle();
    expect(find.text('Страница 38 из 40'), findsOneWidget);
    expect(renders, contains(37));

    await tool(tester, 'Чтение', 'Перейти к странице');
    final number = find.byKey(const Key('reader-jump-number'));
    await tester.enterText(number, '41');
    await press(tester, 'Перейти к странице');
    await tester.pumpAndSettle();
    expect(find.text('Введите число от 1 до 40'), findsOneWidget);
    await tester.enterText(number, '2');
    await press(tester, 'Перейти к странице');
    await tester.pumpAndSettle();
    expect(find.text('Страница 2 из 40'), findsOneWidget);
    expect(renders, contains(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PDF turns along the chosen axis, pans a tall page, and keeps its place in the lazy strip',
    (tester) async {
      final backend = FeaturesBackend({
        'pages': [
          for (var i = 0; i < 40; i++)
            {'width': 595, 'height': i == 1 ? 1400 : 842, 'rotation': 0},
        ],
      });
      final bytes = await backend.create();
      Widget pdf() => NativePdfScreen(
        backend: backend,
        renderer: PdfPageRenderer(allowNonAndroidForTesting: true),
        launch: EditorLaunch(bytes: bytes),
      );
      await setup(tester, const Size(393, 873), 1, pdf());
      final canvas = find.byKey(const Key('pdf-viewport'));
      expect(find.text('Страница 1 из 40'), findsOneWidget);
      await tester.drag(canvas, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(find.text('Страница 2 из 40'), findsOneWidget);

      await changeMode(tester, 'Чтение', ReadingMode.vertical);
      await tester.drag(canvas, const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(find.text('Страница 2 из 40'), findsOneWidget);
      final state = tester.state<PdfViewportState>(find.byType(PdfViewport));
      expect(state.transform.value.storage[13], lessThan(0));
      state.fitPage();
      await tester.pumpAndSettle();
      await tester.drag(canvas, const Offset(0, -190));
      await tester.pumpAndSettle();
      expect(find.text('Страница 3 из 40'), findsOneWidget);
      final before = state.transform.value.getMaxScaleOnAxis();
      await pinch(tester, canvas);
      expect(state.transform.value.getMaxScaleOnAxis(), greaterThan(before));
      expect(find.text('Страница 3 из 40'), findsOneWidget);

      await changeMode(tester, 'Чтение', ReadingMode.continuous);
      final strip = find.byKey(const Key('continuous-pages'));
      expect(strip, findsOneWidget);
      expect(find.text('Страница 3 из 40'), findsOneWidget);
      expect(
        find.byType(PdfPageImage).evaluate().length,
        greaterThanOrEqualTo(2),
      );
      expect(renders.toSet().length, lessThan(8));
      final continuous = tester.state<ContinuousPagesState>(
        find.byType(ContinuousPages),
      );
      await pinch(tester, strip);
      expect(continuous.transform.value.getMaxScaleOnAxis(), greaterThan(1));
      continuous.fitWidth();
      await tester.pumpAndSettle();
      expect(find.text('Страница 3 из 40'), findsOneWidget);
      await tester.drag(strip, const Offset(0, -590));
      await tester.pumpAndSettle();
      expect(find.text('Страница 3 из 40'), findsNothing);
      expect(renders.toSet().length, lessThan(10));

      await tester.pumpWidget(const SizedBox.shrink());
      await setup(tester, const Size(393, 873), 1, pdf());
      expect(strip, findsOneWidget);
      expect(preferences['pdf'], 'continuous');
      expect(find.text('Страница 1 из 40'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Slides swipe on both axes and show multiple slides in continuous reading',
    (tester) async {
      final backend = FeaturesBackend({
        'width': 960,
        'height': 540,
        'slides': [
          for (var i = 0; i < 7; i++)
            {
              'id': i,
              'shapes': [
                {
                  'id': i + 1,
                  'editableText': true,
                  'text': 'Content ${i + 1}',
                  'rect': {'x': 40, 'y': 40, 'w': 700, 'h': 130},
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
      final canvas = find.byKey(const Key('deck-viewport'));
      await tester.drag(canvas, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(find.text('Слайд 2 из 7'), findsOneWidget);
      await changeMode(tester, 'Вид', ReadingMode.vertical);
      await tester.drag(canvas, const Offset(0, -170));
      await tester.pumpAndSettle();
      expect(find.text('Слайд 3 из 7'), findsOneWidget);

      await changeMode(tester, 'Вид', ReadingMode.continuous);
      expect(find.text('Слайд 3 из 7'), findsOneWidget);
      final strip = find.byKey(const Key('continuous-pages'));
      expect(
        find.descendant(of: strip, matching: find.text('Content 4')),
        findsOneWidget,
      );
      await tester.drag(strip, const Offset(0, -270));
      await tester.pumpAndSettle();
      expect(find.text('Слайд 3 из 7'), findsNothing);
      expect(preferences['deck'], 'continuous');
      expect(tester.takeException(), isNull);
    },
  );
}
