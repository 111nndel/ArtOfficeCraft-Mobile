import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:artofficecraft_mobile/ui/grid_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'mobile_viewports_test.dart' show pinch;

void main() {
  testWidgets(
    'Merged overview paint preserves anchor fill instead of covering it with empty cells',
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
                painter: GridOverviewPainter(layout, {
                  'A1': {
                    'display': '',
                    'style': {'fill': '#225599'},
                  },
                  'B2': {
                    'display': '',
                    'style': {'fill': '#FFFFFF'},
                  },
                }, 'A1'),
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
    'Whole-sheet fit is bounded, includes the last row and tap returns to editable cells',
    (tester) async {
      tester.view.physicalSize = const Size(393, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<SheetViewportState>();
      final queries = <GridWindow>[];
      var builtCells = 0;
      (int, int)? tapped;
      final layout = GridLayout(
        GridAxis(232, 68),
        GridAxis(11, 300),
        [],
        usedBounds: const GridBounds(0, 0, 231, 10),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetViewport.cells(
              key: key,
              rowCount: 232,
              columnCount: 11,
              layout: layout,
              corner: const ColoredBox(color: Colors.grey),
              rowHeaderBuilder: (_, r) => const SizedBox(),
              columnHeaderBuilder: (_, c) => const SizedBox(),
              cellBuilder: (_, r, c) {
                builtCells++;
                return const SizedBox();
              },
              overviewBuilder: (_) => const ColoredBox(
                key: Key('overview-test'),
                color: Colors.green,
              ),
              onOverviewTap: (r, c) => tapped = (r, c),
              onWindowChanged: queries.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.fitUsedRange();
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final all = state.zoom;
      expect(all, lessThan(.05));
      expect(
        state.documentPoint(const Offset(393, 700)).dy,
        greaterThanOrEqualTo(232 * 68),
      );
      expect(
        state.documentPoint(const Offset(393, 700)).dx,
        greaterThanOrEqualTo(11 * 300),
      );
      expect(queries.last.overview, isTrue);
      expect(queries.last.rows, 232);
      expect(queries.last.rowIndices, isNull);
      expect(builtCells, lessThan(150));
      tester.view.physicalSize = const Size(700, 393);
      await tester.pumpAndSettle();
      final rotated = state.screenPoint(const Offset(3300, 232 * 68));
      expect(rotated.dx, lessThanOrEqualTo(700));
      expect(rotated.dy, lessThanOrEqualTo(393));
      tester.view.physicalSize = const Size(393, 700);
      await tester.pumpAndSettle();
      state.fitUsedRange(widthOnly: true);
      await tester.pumpAndSettle();
      expect(state.zoom, greaterThan(all));
      expect(
        state.documentPoint(const Offset(393, 700)).dx,
        greaterThanOrEqualTo(3300),
      );
      state.fitUsedRange();
      await tester.pumpAndSettle();
      state.goToCell(200, 5);
      await tester.pumpAndSettle();
      expect(state.zoom, 1, reason: 'Go to cell must leave a fitted overview');
      expect(state.screenPoint(const Offset(1500, 13600)).dy, closeTo(56, .01));
      state.fitUsedRange();
      await tester.pumpAndSettle();
      final target = state.screenPoint(const Offset(3300 / 2, 232 * 68 / 2));
      await tester.tapAt(target);
      await tester.pumpAndSettle();
      expect(tapped!.$1, closeTo(116, 1));
      expect(tapped!.$2, 5);
      expect(state.zoom, 1);
      expect(queries.last.overview, isFalse);
      expect(queries.last.rowIndices!.length, lessThanOrEqualTo(128));
      expect(queries.last.columnIndices!.length, lessThanOrEqualTo(32));
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
