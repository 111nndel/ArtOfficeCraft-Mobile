import 'dart:io';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/main.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Body text keeps readable contrast in both themes', () {
    for (final brightness in Brightness.values) {
      final theme = OfficeTheme.build(brightness);
      final foreground = theme.textTheme.bodyMedium!.color!;
      final background = theme.scaffoldBackgroundColor;
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      final contrast = ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    }
  });

  for (final width in [320.0, 360.0, 393.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Workspace $width dp at ${scale * 100}% remains reachable', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final directory = Directory.systemTemp.createTempSync(
          'aoc-reach-test-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final workspace = WorkspaceStore(directory: directory);
        await tester.runAsync(workspace.load);
        await tester.pumpWidget(
          MaterialApp(
            theme: OfficeTheme.build(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: HomeScreen(
                toggleTheme: () {},
                theme: ThemeMode.light,
                workspace: workspace,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final themeButton = find.byTooltip('Изменить тему');
        expect(tester.getSize(themeButton).width, greaterThanOrEqualTo(52));
        expect(tester.getSize(themeButton).height, greaterThanOrEqualTo(52));
        for (
          var n = 0;
          n < 14 &&
              (find.text('Презентация').evaluate().isEmpty ||
                  tester.getCenter(find.text('Презентация')).dy > 650);
          n++
        ) {
          await tester.drag(
            find.byKey(const PageStorageKey('workspace-scroll')),
            const Offset(0, -240),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.getCenter(find.text('Презентация')).dy, lessThan(700));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Презентация'));
        await tester.pumpAndSettle();
        expect(find.text('Rust недоступен'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Search, filtering and favorites use real stored entries', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('aoc-home-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    late WorkspaceStore store;
    await tester.runAsync(() async {
      store = WorkspaceStore(directory: directory);
      await store.load();
      await store.remember(
        EditorKind.word,
        Uint8List.fromList([1]),
        'План.docx',
      );
      await store.remember(
        EditorKind.excel,
        Uint8List.fromList([2]),
        'Расчёт.xlsx',
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: OfficeTheme.build(Brightness.light),
        home: HomeScreen(
          toggleTheme: () {},
          theme: ThemeMode.light,
          workspace: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Расчёт');
    await tester.pumpAndSettle();
    expect(find.text('Расчёт.xlsx'), findsOneWidget);
    expect(find.text('План.docx'), findsNothing);
    await tester.ensureVisible(find.byTooltip('В избранное'));
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('В избранное'));
      for (
        var n = 0;
        n < 100 &&
            !store.files.firstWhere((f) => f.name == 'Расчёт.xlsx').favorite;
        n++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(
      store.files.firstWhere((f) => f.name == 'Расчёт.xlsx').favorite,
      isTrue,
    );
    await tester.tap(find.byTooltip('Избранное'));
    await tester.pumpAndSettle();
    expect(find.text('Расчёт.xlsx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
