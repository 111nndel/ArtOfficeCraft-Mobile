import 'dart:io';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/l10n/app_strings.dart';
import 'package:artofficecraft_mobile/ui/home_screen.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'draft_test_io.dart';

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.drag(find.byKey(const PageStorageKey('workspace-scroll')), const Offset(0, 4000));
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    target, 250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> historyAction(WidgetTester tester, String action) async {
  final menu = find.byTooltip('Действия с недавними');
  await reveal(tester, menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Future<void> historyTap(WidgetTester tester, WorkspaceStore store, Finder target) =>
    waitDraftIO(tester, () async {
      await tester.tap(target);
      // Queue a no-op behind the UI write, without relying on wall-clock sleeps.
      await store.setRecent(const [], true);
    });

void main() {
  Future<(WorkspaceStore, DraftStore, WorkspaceFile, WorkspaceFile)> fixture(
    WidgetTester tester, {
    double scale = 1,
    String language = 'ru',
  }) async {
    final values = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('aoc-history-ui-');
      addTearDown(() => directory.delete(recursive: true));
      final workspace = WorkspaceStore(
        directory: await Directory('${directory.path}/files').create(),
      );
      await workspace.load();
      final word = await workspace.remember(
        EditorKind.word, Uint8List.fromList([1]), 'Plan.docx',
      );
      final grid = await workspace.remember(
        EditorKind.excel, Uint8List.fromList([2]), 'Budget.xlsx',
      );
      await workspace.toggleFavorite(word);
      final drafts = DraftStore(directory: Directory('${directory.path}/drafts'));
      await drafts.load();
      await drafts.write(
        id: 'r0123456789abcdef0123456789abcdef',
        kind: EditorKind.word,
        name: 'Draft.docx',
        bytes: Uint8List.fromList([3]),
        editor: {'text': 'Unsaved text'},
      );
      return (workspace, drafts, word, grid);
    }))!;
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: OfficeTheme.build(Brightness.dark),
      locale: Locale(language),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HomeScreen(
        toggleTheme: () {},
        theme: ThemeMode.dark,
        workspace: values.$1,
        drafts: values.$2,
      ),
    ));
    await tester.pumpAndSettle();
    return values;
  }

  testWidgets('Clear confirms, can be undone, and retains files, favorites and recovery',
    (tester) async {
      final (store, drafts, word, grid) = await fixture(tester);
      await historyAction(tester, 'Очистить все недавние');
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(store.files.every((f) => f.recent), isTrue);

      await historyAction(tester, 'Очистить все недавние');
      await historyTap(tester, store, find.text('Очистить'));
      await tester.pumpAndSettle();
      expect(store.files.every((f) => !f.recent), isTrue);
      expect(find.text('Plan.docx'), findsNothing);
      expect(find.text('Budget.xlsx'), findsNothing);
      expect(drafts.items, hasLength(1));
      expect(await tester.runAsync(() => store.read(word)), [1]);
      expect(await tester.runAsync(() => store.read(grid)), [2]);
      await historyTap(tester, store, find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(store.files.every((f) => f.recent), isTrue);

      await historyAction(tester, 'Очистить все недавние');
      await historyTap(tester, store, find.text('Очистить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Файлы'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Plan.docx'));
      expect(find.text('Рабочие копии'), findsOneWidget);
      await reveal(tester, find.text('Budget.xlsx'));
      await tester.tap(find.byTooltip('Избранное'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Plan.docx'));
      expect(find.text('Budget.xlsx'), findsNothing);
      expect(store.files.singleWhere((f) => f.id == word.id).favorite, isTrue);
      expect(drafts.items.single.name, 'Draft.docx');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Selection removes only visible filtered entries and resets on navigation',
    (tester) async {
      final (store, _, word, grid) = await fixture(tester);
      await reveal(tester, find.widgetWithText(ChoiceChip, 'Документ'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Документ'));
      await tester.pumpAndSettle();
      await historyAction(tester, 'Выбрать документы');
      await reveal(tester, find.text('Выбрать все'));
      await tester.tap(find.text('Выбрать все'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрано: 1'), findsOneWidget);
      await historyTap(tester, store, find.text('Убрать из недавних'));
      await tester.pumpAndSettle();
      expect(store.files.singleWhere((f) => f.id == word.id).recent, isFalse);
      expect(store.files.singleWhere((f) => f.id == grid.id).recent, isTrue);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Все'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(ValueKey('workspace-${grid.id}')));
      await tester.longPress(find.text('Budget.xlsx'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('select-${grid.id}')), findsOneWidget);
      await tester.tap(find.byTooltip('Файлы'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(store.files.singleWhere((f) => f.id == grid.id).recent, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ru', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('History selection fits 320dp at scale $scale in $language',
        (tester) async {
          await fixture(tester, scale: scale, language: language);
          final menu = find.byTooltip(language == 'en'
              ? 'Recent file actions' : 'Действия с недавними');
          await reveal(tester, menu);
          expect(tester.getSize(menu).width, greaterThanOrEqualTo(48));
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text(language == 'en'
              ? 'Select documents' : 'Выбрать документы'));
          await tester.pumpAndSettle();
          final all = find.text(language == 'en' ? 'Select all' : 'Выбрать все');
          await reveal(tester, all);
          await tester.tap(all);
          await tester.pumpAndSettle();
          expect(find.text(language == 'en' ? 'Selected: 2' : 'Выбрано: 2'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
