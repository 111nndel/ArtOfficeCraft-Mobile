import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:artofficecraft_mobile/ui/grid_cells_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'mobile_viewports_test.dart' show pinch;

void main() {
  testWidgets(
    'Merged cell paint preserves anchor fill instead of covering it with empty cells',
    (tester) async {
      final boundary = GlobalKey();
      final layout = GridLayout(GridAxis(2, 40), GridAxis(2, 40), [
        const GridMerge(0, 0, 1, 1),
      ], showGridlines: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: CustomPaint(
                size: const Size(80, 80),
                painter: GridCellsPainter(
                  layout,
                  {
                    'A1': {
                      'display': '',
                      'style': {'fill': '#225599'},
                    },
                    'B2': {
                      'display': '',
                      'style': {'fill': '#FFFFFF'},
                    },
                  },
                  'A1',
                  viewport: const Rect.fromLTWH(0, 0, 80, 80),
                  scale: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final picture =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (20 * 80 + 20) * 4;
        expect(
          [
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          ],
          [0x22, 0x55, 0x99],
        );
        picture.dispose();
      });
    },
  );
  testWidgets(
    'Reduced zoom keeps empty grid editable and never centers or changes zoom on tap',
    (tester) async {
      tester.view.physicalSize = const Size(393, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<SheetViewportState>();
      final queries = <GridWindow>[];
      (int, int)? tapped;
      var builtCells = 0;
      final layout = GridLayout(
        GridAxis(gridMaxRows, 20),
        GridAxis(gridMaxColumns, 64),
        [],
        usedBounds: const GridBounds(0, 0, 10, 3),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetViewport.cells(
              key: key,
              rowCount: gridMaxRows,
              columnCount: gridMaxColumns,
              layout: layout,
              corner: const SizedBox(),
              rowHeaderBuilder: (_, r) => const SizedBox(),
              columnHeaderBuilder: (_, c) => const SizedBox(),
              cellBuilder: (_, r, c) {
                builtCells++;
                return const SizedBox();
              },
              compactCellsBuilder: (_, rect, rows, columns) => CustomPaint(
                painter: GridCellsPainter(
                  layout,
                  const {},
                  'A1',
                  viewport: rect,
                  scale: key.currentState!.zoom,
                ),
              ),
              onCellTap: (r, c) => tapped = (r, c),
              onWindowChanged: queries.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final before = builtCells;
      state.setZoom(.1);
      await tester.pumpAndSettle();
      expect(state.screenPoint(Offset.zero), const Offset(52, 56));
      expect(queries.last.rowIndices!.last, greaterThan(300));
      expect(queries.last.columnIndices!.last, greaterThan(40));
      expect(
        builtCells,
        before,
        reason: 'Do not lay out thousands of tiny widgets',
      );
      await tester.tapAt(
        state.screenPoint(const Offset(20 * 64 + 32, 100 * 20 + 10)),
      );
      await tester.pumpAndSettle();
      expect(tapped, (100, 20));
      expect(state.zoom, .1);
      state.goToCell(900, 100);
      await tester.pumpAndSettle();
      expect(state.zoom, .1);
      expect(
        state.documentPoint(const Offset(52, 56)),
        const Offset(6400, 18000),
      );
      expect(queries.last.row, greaterThan(800));
      state.setZoom(.000001);
      await tester.pumpAndSettle();
      expect(state.zoom, .1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Headings leave the sheet edge, optional pinning works and pinch keeps the focal cell',
    (tester) async {
      final key = GlobalKey<SheetViewportState>();
      var pinned = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return SheetViewport.cells(
                  key: key,
                  rowCount: 10000,
                  columnCount: 100,
                  freezeHeadings: pinned,
                  layout: GridLayout(
                    GridAxis(10000, 30),
                    GridAxis(100, 90),
                    [],
                  ),
                  corner: const ColoredBox(color: Colors.grey),
                  rowHeaderBuilder: (_, r) => const SizedBox(),
                  columnHeaderBuilder: (_, c) => const SizedBox(),
                  cellBuilder: (_, r, c) => const SizedBox(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      state.goToCell(20, 5);
      await tester.pumpAndSettle();
      final corner = find.byKey(const ValueKey('grid-corner'));
      expect(tester.getRect(corner).right, lessThan(0));
      expect(tester.getRect(corner).bottom, lessThan(0));
      final center = tester.getCenter(find.byKey(const Key('sheet-viewport')));
      final before = state.documentPoint(center);
      await pinch(tester, find.byKey(const Key('sheet-viewport')));
      expect(state.zoom, greaterThan(1.5));
      expect((state.documentPoint(center) - before).distance, lessThan(1));
      rebuild(() => pinned = true);
      await tester.pumpAndSettle();
      expect(tester.getRect(corner).topLeft, Offset.zero);
      await tester.fling(
        find.byKey(const Key('sheet-viewport')),
        const Offset(-80, -100),
        800,
      );
      final released = Offset(
        state.transform.value.storage[12],
        state.transform.value.storage[13],
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 50));
      final moving = Offset(
        state.transform.value.storage[12],
        state.transform.value.storage[13],
      );
      expect((moving - released).distance, greaterThan(0));
      final finger = await tester.startGesture(center);
      await tester.pump();
      final stopped = Offset(
        state.transform.value.storage[12],
        state.transform.value.storage[13],
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        Offset(
          state.transform.value.storage[12],
          state.transform.value.storage[13],
        ),
        stopped,
      );
      await finger.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
