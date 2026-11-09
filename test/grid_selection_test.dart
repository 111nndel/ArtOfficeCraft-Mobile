import 'package:artofficecraft_mobile/native/grid_selection.dart';
import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_viewports_test.dart' show pinch;

void main() {
  test('Range parsing normalizes endpoints, validates Excel limits and expands chained merges', () {
    expect(GridSelection.parse(r'$D$5:$B$2')!.address, 'B2:D5');
    expect(GridSelection.parse('XFD1048576')!.cellCount, 1);
    for (final input in ['A0:B2', 'XFE1:B2', 'A1:B2:C3', 'A1:', 'A1048577']) {
      expect(GridSelection.parse(input), isNull);
    }
    final layout = GridLayout(GridAxis(100, 30), GridAxis(20, 60), [
      const GridMerge(1, 1, 3, 3),
      const GridMerge(3, 4, 6, 5),
    ]);
    final value = const GridSelection(2, 2, 4, 4).includingMerges(layout);
    expect(value.address, 'B2:F7');
    expect(value.cellCount, 30);
  });
  Future<void> open(
    WidgetTester tester,
    GlobalKey<SheetViewportState> key,
    GridSelection initial,
    ValueChanged<GridSelection> changed,
  ) async {
    var selection = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              height: 420,
              child: StatefulBuilder(
                builder: (context, set) => SheetViewport.cells(
                  key: key,
                  rowCount: 1000,
                  columnCount: 100,
                  rowExtent: 30,
                  columnExtent: 60,
                  rowHeaderExtent: 32,
                  columnHeaderExtent: 28,
                  cellBuilder: (_, r, c) => const SizedBox(),
                  columnHeaderBuilder: (_, i) => const SizedBox(),
                  rowHeaderBuilder: (_, i) => const SizedBox(),
                  corner: const SizedBox(),
                  selection: selection,
                  onSelectionChanged: (value) {
                    set(() => selection = value);
                    changed(value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Finger handles grow and shrink a range without zooming or moving the sheet',
    (tester) async {
      final key = GlobalKey<SheetViewportState>();
      var value = const GridSelection(1, 1, 2, 2);
      await open(tester, key, value, (v) => value = v);
      final handle = find.byKey(const ValueKey('grid-selection-end'));
      expect(tester.getSize(handle), const Size(44, 44));
      await tester.drag(handle, const Offset(60, 60));
      await tester.pumpAndSettle();
      expect(value.address, 'B2:D5');
      expect(key.currentState!.zoom, 1);
      expect(key.currentState!.transform.value.storage[13], 0);
      await tester.drag(handle, const Offset(-60, -30));
      await tester.pumpAndSettle();
      expect(value.address, 'B2:C4');
      await tester.drag(
        find.byKey(const ValueKey('grid-selection-start')),
        const Offset(60, 30),
      );
      await tester.pumpAndSettle();
      expect(value.address, 'C3:C4');
      await pinch(tester, find.byKey(const Key('sheet-viewport')));
      expect(value.address, 'C3:C4');
      expect(key.currentState!.zoom, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Holding a range handle near the edge scrolls to more rows and stops on release',
    (tester) async {
      final key = GlobalKey<SheetViewportState>();
      var value = const GridSelection(1, 1, 8, 2);
      await open(tester, key, value, (v) => value = v);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('grid-selection-end'))),
      );
      await gesture.moveTo(const Offset(230, 410));
      await tester.pump(const Duration(milliseconds: 20));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(key.currentState!.transform.value.storage[13], lessThan(-100));
      expect(value.endRow, greaterThan(12));
      expect(key.currentState!.zoom, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      final after = key.currentState!.transform.value.storage[13];
      await tester.pump(const Duration(seconds: 1));
      expect(key.currentState!.transform.value.storage[13], after);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
