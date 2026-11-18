import 'dart:convert';
import 'dart:io';

import 'package:artofficecraft_mobile/main.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Compact home labels are truthful on a 320 dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(toggleTheme: () {}, theme: ThemeMode.system),
      ),
    );
    expect(find.text('Создать файл'), findsOneWidget);
    expect(find.text('Рабочие пространства'), findsNothing);
    expect(find.textContaining('Настоящие файлы Office ещё'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Long file lists build nearby cards and sort filtered results', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('aoc-file-order-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final copies = [
      for (var i = 1; i <= 200; i++)
        WorkspaceFile(
          id: 'f$i',
          name: switch (i) {
            1 => 'План Я.xlsx',
            200 => 'план А.xlsx',
            _ => 'Книга $i.xlsx',
          },
          kind: EditorKind.excel,
          modified: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          favorite: i == 1 || i == 200,
        ),
    ];
    final (files, drafts) = (await tester.runAsync(() async {
      final files = WorkspaceStore(directory: directory);
      final drafts = DraftStore(
        directory: Directory('${directory.path}/drafts'),
      );
      for (final copy in copies) {
        File('${directory.path}/${copy.id}.xlsx').writeAsBytesSync([1]);
      }
      File('${directory.path}/index.json').writeAsStringSync(
        jsonEncode(copies.map((copy) => copy.toJson()).toList()),
      );
      await files.load();
      await drafts.load();
      return (files, drafts);
    }))!;
    addTearDown(files.dispose);
    addTearDown(drafts.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          toggleTheme: () {},
          theme: ThemeMode.light,
          workspace: files,
          drafts: drafts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Файлы'));
    await tester.pumpAndSettle();

    final allCards = find.byWidgetPredicate(
      (widget) =>
          widget is Card && widget.key.toString().contains('workspace-f'),
    );
    final firstCard = find.byKey(const ValueKey('workspace-f200'));
    await tester.scrollUntilVisible(
      firstCard,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(allCards.evaluate().length, inInclusiveRange(1, 29));
    expect(find.byKey(const ValueKey('workspace-f1')), findsNothing);
    await tester.drag(
      find.byKey(const PageStorageKey('workspace-scroll')),
      const Offset(0, 1800),
    );
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    await tester.enterText(search, 'ПЛАН');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final newName = find.text('план А.xlsx'),
        oldName = find.text('План Я.xlsx');
    Future<void> sort(String label) async {
      await tester.tap(find.byTooltip('Сортировка файлов'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await sort('Сначала старые');
    expect(
      tester.getTopLeft(oldName).dy,
      lessThan(tester.getTopLeft(newName).dy),
    );
    await sort('По имени');
    expect(
      tester.getTopLeft(newName).dy,
      lessThan(tester.getTopLeft(oldName).dy),
    );
    await tester.tap(find.byTooltip('Избранное'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(newName).dy,
      lessThan(tester.getTopLeft(oldName).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
