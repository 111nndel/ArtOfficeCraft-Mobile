import 'dart:math';

import 'package:artofficecraft_mobile/native/grid_layout.dart';
import 'package:artofficecraft_mobile/native/grid_selection.dart';
import 'package:flutter_test/flutter_test.dart';

GridBounds randomBounds(Random random) {
  final row = random.nextInt(11000), column = random.nextInt(40);
  return GridBounds(
    row,
    column,
    row + random.nextInt(64),
    column + random.nextInt(8),
  );
}

void main() {
  test(
    'Merge index matches linear lookup for unsorted intervals and boundaries',
    () {
      final random = Random(50);
      final merges = [
        const GridMerge(0, 4, 1048575, 4),
        const GridMerge(4, 0, 4, 16383),
        for (var i = 0; i < 1000; i++)
          GridMerge(i * 10, i % 32, i * 10 + 2, i % 32 + 2),
      ]..shuffle(random);
      final layout = GridLayout(
        GridAxis(1048576, 20),
        GridAxis(16384, 64),
        merges,
      );
      final queries = [
        const GridBounds(0, 0, 0, 0),
        const GridBounds(1048575, 4, 1048575, 4),
        const GridBounds(4, 16383, 4, 16383),
        for (final m in merges.take(20))
          GridBounds(m.endRow, m.endColumn, m.endRow, m.endColumn),
        for (var i = 0; i < 2000; i++) randomBounds(random),
      ];
      for (final q in queries) {
        final expected = merges
            .where(
              (m) =>
                  m.row <= q.endRow &&
                  m.endRow >= q.row &&
                  m.column <= q.endColumn &&
                  m.endColumn >= q.column,
            )
            .toList();
        expect(layout.mergesIn(q), orderedEquals(expected));
        expect(
          layout.mergeAt(q.row, q.column),
          merges.where((m) => m.contains(q.row, q.column)).firstOrNull,
        );
      }
    },
  );

  test(
    'Merge snapshots stay immutable and independent after a replacement',
    () {
      final rows = GridAxis(100, 20), columns = GridAxis(30, 64);
      final source = [const GridMerge(2, 3, 4, 5)];
      final before = GridLayout(rows, columns, source);
      expect(before.mergeAt(4, 5), same(source.single));
      source.clear();
      final after = GridLayout(rows, columns, source);
      expect(before.mergeAt(4, 5), isNotNull);
      expect(after.mergeAt(4, 5), isNull);
      expect(before.mergeAt(5, 5), isNull);
      expect(() => before.merges.clear(), throwsUnsupportedError);
    },
  );

  test('Range expansion finds chained merges among many distant intervals', () {
    final layout = GridLayout(GridAxis(1048576, 20), GridAxis(16384, 64), [
      for (var i = 0; i < 10000; i++)
        GridMerge(100 + i * 10, 20, 102 + i * 10, 22),
      const GridMerge(3, 4, 6, 5),
      const GridMerge(1, 1, 3, 3),
    ]);
    expect(
      const GridSelection(2, 2, 4, 4).includingMerges(layout).address,
      'B2:F7',
    );
  });
}
