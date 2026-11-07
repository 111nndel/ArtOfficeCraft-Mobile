import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_editing_test.dart' as grid;

void main() {
  testWidgets(
    'Document headings stay compact with large system text and sheet zoom',
    (tester) async {
      final backend = grid.MemoryGrid();
      await grid.open(tester, backend);
      final context = tester.element(find.byType(SheetViewport));
      final scale = MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          builder: (_, child) => MediaQuery(data: scale, child: child!),
          home: NativeGridScreen(
            backend: backend,
            launch: const EditorLaunch(create: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.state<SheetViewportState>(
        find.byType(SheetViewport),
      );
      final heading = find.byKey(const ValueKey('grid-column-header-0'));
      final label = find.descendant(of: heading, matching: find.byType(Text));
      expect(tester.getSize(heading).height, 28);
      expect(tester.widget<Text>(label).style!.fontSize, 11);
      expect(tester.widget<Text>(label).textScaler!.scale(11), 11);
      viewport.setZoom(5);
      await tester.pumpAndSettle();
      expect(tester.getSize(heading).height, 28);
      expect(
        tester.getSize(find.byKey(const ValueKey('grid-row-header-0'))).width,
        46,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A failed window read preserves pending input and clears when returning to loaded cells',
    (tester) async {
      final backend = grid.MemoryGrid();
      await grid.open(tester, backend);
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'do not lose');
      backend.failInspect = true;
      final viewport = tester.state<SheetViewportState>(
        find.byType(SheetViewport),
      );
      viewport.goToCell(999, 26);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('Повторить загрузку области'), findsOneWidget);
      expect(tester.widget<TextField>(formula).controller!.text, 'do not lose');
      expect(backend.requests, isEmpty);
      viewport.goToCell(0, 0);
      await tester.pumpAndSettle();
      expect(find.text('Повторить загрузку области'), findsNothing);
      expect(tester.widget<TextField>(formula).controller!.text, 'do not lose');
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'A1 coordinates cover Excel bounds and buffer requests stay bounded',
    () {
      expect(gridAddress(r'$aa$1000'), (row: 999, column: 26));
      expect(gridAddress('XFD1048576'), (
        row: gridMaxRows - 1,
        column: gridMaxColumns - 1,
      ));
      for (final value in ['A0', 'XFE1', 'A1048577', 'AA-1']) {
        expect(gridAddress(value), isNull);
      }
      final end = const GridWindow(
        0,
        gridMaxRows - 1,
        gridMaxColumns - 1,
        rows: 1,
        columns: 1,
      ).buffered;
      expect(end.contains(gridMaxRows - 1, gridMaxColumns - 1), isTrue);
      expect(end.row + end.rows, lessThanOrEqualTo(gridMaxRows));
      expect(end.column + end.columns, lessThanOrEqualTo(gridMaxColumns));
      expect(end.rows * end.columns, lessThanOrEqualTo(4096));
    },
  );
  testWidgets(
    'Distant sheet areas mount only visible cells and preserve pending input',
    (tester) async {
      final backend = grid.MemoryGrid();
      await grid.open(tester, backend);
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'pending at A1');
      final viewport = tester.state<SheetViewportState>(
        find.byType(SheetViewport),
      );
      viewport.goToCell(999, 26);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('grid-cell-AA1000')), findsOneWidget);
      expect(find.byKey(const ValueKey('grid-cell-A1')), findsNothing);
      expect(
        tester.widget<TextField>(formula).controller!.text,
        'pending at A1',
      );
      expect(backend.requests, isEmpty);
      final mountedCells = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((w) => w.key.toString().contains('grid-cell-'));
      expect(mountedCells.length, lessThan(250));
      await tester.tap(find.byKey(const ValueKey('grid-cell-AA1000')));
      await tester.pumpAndSettle();
      expect(
        backend.last!['sheets'][0]['cells']['A1']['input'],
        'pending at A1',
      );
      await tester.enterText(formula, 'edited at AA1000');
      await tester.tap(find.byTooltip('Применить'));
      await tester.pumpAndSettle();
      expect(
        backend.last!['sheets'][0]['cells']['AA1000']['input'],
        'edited at AA1000',
      );
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(
        (backend.last!['sheets'][0]['cells'] as Map).containsKey('AA1000'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Go to cell validates input and reveals the last Excel address in the slab',
    (tester) async {
      final backend = grid.MemoryGrid();
      await grid.open(tester, backend);
      final formula = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(formula, 'keep pending');
      await tester.tap(find.byKey(const Key('tool-section-caption')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вид'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перейти к ячейке'));
      await tester.pumpAndSettle();
      final address = find.byKey(const Key('grid-address-input'));
      await tester.enterText(address, 'XFE1');
      await tester.tap(find.text('Перейти'));
      await tester.pumpAndSettle();
      expect(backend.requests, isEmpty);
      expect(
        tester.widget<TextField>(formula).controller!.text,
        'keep pending',
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(address, 'XFD1048576');
      await tester.tap(find.text('Перейти'));
      await tester.pumpAndSettle();
      expect(
        backend.last!['sheets'][0]['cells']['A1']['input'],
        'keep pending',
      );
      expect(
        find.byKey(const ValueKey('grid-cell-XFD1048576')),
        findsOneWidget,
      );
      final bounds = tester.getRect(find.byKey(const Key('sheet-viewport')));
      expect(
        bounds.contains(
          tester.getCenter(find.byKey(const ValueKey('grid-cell-XFD1048576'))),
        ),
        isTrue,
      );
      expect(tester.widget<TextField>(formula).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
