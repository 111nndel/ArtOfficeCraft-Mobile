import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_viewports_test.dart' show pinch;

void main() {
  test(
    'Sparse geometry handles hidden blocks, distant positions and resize',
    () {
      final axis = GridAxis(gridMaxRows, 20, [
        [0, 0, 50],
        [2, 999998, 0],
        [999999, 999999, 80],
      ]);
      expect(axis.offset(1), 50);
      expect(axis.offset(999999), 70);
      expect(axis.indexAt(70), 999999);
      expect(axis.visible(0, 150, buffer: 0), [0, 1, 999999]);
      final changed = axis.resized(1, 90);
      expect(changed.offset(999999), 140);
      expect(changed.extent(2), 0);
      expect(
        axis.extent(1),
        20,
        reason: 'preview does not mutate imported geometry',
      );
      final window = GridWindow.visible(0, [0, 1, 999999], [0, 2]);
      expect(window.contains(999999, 2), isTrue);
      expect(window.contains(500, 1), isFalse);
      expect(window.covers(GridWindow.visible(0, [999999], [2])), isTrue);
      expect(window.request('A1')['rowIndices'], [0, 1, 999999]);
    },
  );
  testWidgets(
    'Merged imported geometry and finger resize coexist with pinch and pan',
    (tester) async {
      tester.view.physicalSize = const Size(393, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var layout = GridLayout(
        GridAxis(2000, 30, [
          [0, 0, 60],
          [2, 2, 0],
        ]),
        GridAxis(100, 80, [
          [0, 0, 120],
          [1, 1, 0],
        ]),
        [const GridMerge(0, 0, 1, 2)],
      );
      final calls = <({bool row, int index, double size})>[];
      final key = GlobalKey<SheetViewportState>();
      late StateSetter rebuild;
      var selected = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SheetViewport.cells(
                  key: key,
                  rowCount: 2000,
                  columnCount: 100,
                  layout: layout,
                  corner: const ColoredBox(color: Colors.grey),
                  rowHeaderBuilder: (_, r) =>
                      ColoredBox(color: Colors.grey, child: Text('${r + 1}')),
                  columnHeaderBuilder: (_, c) => ColoredBox(
                    color: Colors.grey,
                    child: Text(gridColumnName(c)),
                  ),
                  cellBuilder: (_, r, c) => GestureDetector(
                    key: ValueKey('cell-$r-$c'),
                    onTap: () => selected = '$r:$c',
                    child: const ColoredBox(color: Colors.white),
                  ),
                  onResize: (row, index, size) async {
                    calls.add((row: row, index: index, size: size));
                    rebuild(
                      () => layout = GridLayout(
                        row ? layout.rows.resized(index, size) : layout.rows,
                        row
                            ? layout.columns
                            : layout.columns.resized(index, size),
                        layout.merges,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('cell-0-0'))),
        const Size(200, 90),
      );
      expect(
        find.byKey(const ValueKey('cell-1-2')),
        findsNothing,
        reason: 'covered cells are not duplicated',
      );
      expect(find.byKey(const ValueKey('grid-row-header-2')), findsNothing);
      final head = find.byKey(const ValueKey('grid-column-header-0'));
      final g = await tester.startGesture(tester.getCenter(head));
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(calls.single, (row: false, index: 0, size: 200.0));
      expect(tester.getSize(find.byKey(const ValueKey('cell-0-0'))).width, 280);
      final rowHead = find.byKey(const ValueKey('grid-row-header-0'));
      final r = await tester.startGesture(tester.getCenter(rowHead));
      await tester.pump(const Duration(milliseconds: 600));
      await r.moveBy(const Offset(0, -24));
      await tester.pump();
      await r.up();
      await tester.pumpAndSettle();
      expect(calls.last, (row: true, index: 0, size: 36.0));
      await tester.tap(find.byKey(const ValueKey('cell-0-0')));
      expect(selected, '0:0');
      await pinch(tester, find.byKey(const Key('sheet-viewport')));
      expect(key.currentState!.zoom, greaterThan(1.5));
      key.currentState!.goToCell(0, 0);
      await tester.pumpAndSettle();
      final fixedRow = find.byKey(const ValueKey('grid-row-header-0'));
      final fixedColumn = find.byKey(const ValueKey('grid-column-header-0'));
      expect(
        tester.getBottomRight(fixedRow).dx - tester.getTopLeft(fixedRow).dx,
        closeTo(52, .01),
      );
      expect(
        tester.getBottomRight(fixedColumn).dy -
            tester.getTopLeft(fixedColumn).dy,
        closeTo(56, .01),
      );
      key.currentState!.setZoom(5);
      await tester.pumpAndSettle();
      // Headings keep touch space at maximum zoom, leaving room for the sheet.
      final corner = find.byKey(const ValueKey('grid-corner'));
      expect(
        tester.getBottomRight(corner).dx - tester.getTopLeft(corner).dx,
        closeTo(52, .01),
      );
      key.currentState!.setZoom(1);
      await tester.pumpAndSettle();
      key.currentState!.goToCell(1, 2);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cell-0-0')),
        findsOneWidget,
        reason: 'merge anchor survives partial visibility',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
