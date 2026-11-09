import 'dart:math' as math;

import 'grid_layout.dart';
import 'grid_window.dart';

/// A single rectangular mobile selection, in inclusive sheet coordinates.
class GridSelection extends GridBounds {
  const GridSelection(super.row, super.column, super.endRow, super.endColumn);
  factory GridSelection.between(
    int row,
    int column,
    int otherRow,
    int otherColumn,
  ) => GridSelection(
    math.min(row, otherRow),
    math.min(column, otherColumn),
    math.max(row, otherRow),
    math.max(column, otherColumn),
  );
  static GridSelection? parse(String text) {
    final parts = text.trim().split(':');
    if (parts.isEmpty || parts.length > 2) return null;
    final first = gridAddress(parts.first), last = gridAddress(parts.last);
    if (first == null || last == null) return null;
    return GridSelection.between(
      first.row,
      first.column,
      last.row,
      last.column,
    );
  }

  static const maxCells = 4096;
  int get cellCount => (endRow - row + 1) * (endColumn - column + 1);
  String get address =>
      '${gridColumnName(column)}${row + 1}:${gridColumnName(endColumn)}${endRow + 1}';
  GridSelection includingMerges(GridLayout layout) {
    var a = row, b = column, c = endRow, d = endColumn;
    var changed = true;
    while (changed) {
      changed = false;
      for (final m in layout.merges) {
        if (m.row > c || m.endRow < a || m.column > d || m.endColumn < b) {
          continue;
        }
        final na = math.min(a, m.row),
            nb = math.min(b, m.column),
            nc = math.max(c, m.endRow),
            nd = math.max(d, m.endColumn);
        if (na != a || nb != b || nc != c || nd != d) {
          a = na;
          b = nb;
          c = nc;
          d = nd;
          changed = true;
          if ((c - a + 1) * (d - b + 1) > maxCells) {
            return GridSelection(a, b, c, d);
          }
        }
      }
    }
    return GridSelection(a, b, c, d);
  }
}
