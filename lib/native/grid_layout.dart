import 'dart:math' as math;

import 'grid_window.dart';

/// Sparse axis geometry in document pixels (96 dpi), including hidden lines.
/// Prefix corrections keep distant-cell lookup independent of the row count.
class GridAxis {
  GridAxis(this.count, this.defaultExtent, [List<List<num>> runs = const []]) {
    var correction = 0.0;
    for (final run in runs) {
      final start = run[0].toInt(), end = run[1].toInt();
      final size = run[2].toDouble();
      if (start < 0 ||
          end < start ||
          end >= count ||
          !size.isFinite ||
          size < 0 ||
          (_ends.isNotEmpty && start <= _ends.last)) {
        throw const FormatException('Invalid sheet axis');
      }
      _starts.add(start);
      _ends.add(end);
      _sizes.add(size);
      _before.add(correction);
      correction += (end - start + 1) * (size - defaultExtent);
      _after.add(correction);
    }
  }
  final int count;
  final double defaultExtent;
  final _starts = <int>[], _ends = <int>[];
  final _sizes = <double>[], _before = <double>[], _after = <double>[];
  int _run(int index) {
    var lo = 0, hi = _starts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_starts[mid] <= index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  double extent(int index) {
    final r = _run(index);
    return r >= 0 && index <= _ends[r] ? _sizes[r] : defaultExtent;
  }

  double offset(int index) {
    final r = _run(index);
    if (r < 0) return index * defaultExtent;
    final correction = index <= _ends[r]
        ? _before[r] + (index - _starts[r]) * (_sizes[r] - defaultExtent)
        : _after[r];
    return index * defaultExtent + correction;
  }

  double get total => offset(count);
  int indexAt(double position) {
    var lo = 0, hi = count;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (offset(mid + 1) <= position) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo.clamp(0, count - 1);
  }

  List<int> visible(double start, double end, {int buffer = 2}) {
    final result = <int>[];
    var index = indexAt(start.clamp(0, total));
    for (var n = 0; n < buffer && index > 0; n++) {
      index = indexAt((offset(index) - .001).clamp(0, total));
    }
    var trailing = 0;
    while (index < count) {
      final size = extent(index);
      if (size > 0) {
        if (offset(index) >= end && trailing++ >= buffer) break;
        result.add(index);
        index++;
      } else {
        // Skip a million hidden rows without walking through them.
        final run = _run(index);
        index = run >= 0 && index <= _ends[run] ? _ends[run] + 1 : index + 1;
      }
    }
    return result;
  }

  GridAxis resized(int index, double size) {
    final runs = <List<num>>[];
    for (var r = 0; r < _starts.length; r++) {
      final start = _starts[r], end = _ends[r];
      if (index < start || index > end) {
        runs.add([start, end, _sizes[r]]);
      } else {
        if (start < index) runs.add([start, index - 1, _sizes[r]]);
        if (index < end) runs.add([index + 1, end, _sizes[r]]);
      }
    }
    runs.add([index, index, size]);
    runs.sort((a, b) => a[0].compareTo(b[0]));
    return GridAxis(count, defaultExtent, runs);
  }
}

class GridMerge {
  const GridMerge(this.row, this.column, this.endRow, this.endColumn);
  final int row, column, endRow, endColumn;
  bool contains(int r, int c) =>
      r >= row && r <= endRow && c >= column && c <= endColumn;
  String get address => '${gridColumnName(column)}${row + 1}';
}

class GridBounds {
  const GridBounds(this.row, this.column, this.endRow, this.endColumn);
  final int row, column, endRow, endColumn;
  RectInSheet pixels(GridAxis rows, GridAxis columns) => RectInSheet(
    columns.offset(column),
    rows.offset(row),
    columns.offset(endColumn + 1),
    rows.offset(endRow + 1),
  );
}

class RectInSheet {
  const RectInSheet(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get width => right - left;
  double get height => bottom - top;
}

class GridLayout {
  GridLayout(
    this.rows,
    this.columns,
    List<GridMerge> merges, {
    this.showGridlines = true,
    this.usedBounds,
    this.tables = const [],
  }) : merges = List.unmodifiable(merges);
  factory GridLayout.fromJson(Map? json) {
    List<List<num>> runs(String key) => (json?[key] as List? ?? [])
        .map((v) => List<num>.from(v as List))
        .toList();
    return GridLayout(
      GridAxis(
        gridMaxRows,
        (json?['defaultRowHeight'] as num?)?.toDouble() ?? 56,
        runs('rows'),
      ),
      GridAxis(
        gridMaxColumns,
        (json?['defaultColumnWidth'] as num?)?.toDouble() ?? 116,
        runs('columns'),
      ),
      (json?['merges'] as List? ?? [])
          .map(
            (v) =>
                GridMerge(v[0] as int, v[1] as int, v[2] as int, v[3] as int),
          )
          .toList(),
      showGridlines: json?['showGridlines'] != false,
      tables: (json?['tables'] as List? ?? [])
          .map(
            (v) =>
                GridBounds(v[0] as int, v[1] as int, v[2] as int, v[3] as int),
          )
          .toList(),
      usedBounds:
          json?['usedRange'] is List && (json!['usedRange'] as List).length == 4
          ? GridBounds(
              (json['usedRange'][0] as num).toInt(),
              (json['usedRange'][1] as num).toInt(),
              (json['usedRange'][2] as num).toInt(),
              (json['usedRange'][3] as num).toInt(),
            )
          : null,
    );
  }
  final GridAxis rows, columns;
  final List<GridMerge> merges;
  final List<GridBounds> tables;
  final bool showGridlines;
  final GridBounds? usedBounds;

  // A balanced interval tree stored in two arrays. Build once per immutable
  // layout; subtree end rows prune distant merges without expanding cells.
  late final _mergeOrder = List.generate(merges.length, (i) => i)
    ..sort((a, b) {
      final order = merges[a].row.compareTo(merges[b].row);
      return order == 0 ? a.compareTo(b) : order;
    });
  late final _mergeEnds = _indexMerges();
  List<int> _indexMerges() {
    final ends = List.filled(merges.length, -1);
    int build(int lo, int hi) {
      if (lo >= hi) return -1;
      final mid = (lo + hi) ~/ 2;
      return ends[mid] = math.max(
        merges[_mergeOrder[mid]].endRow,
        math.max(build(lo, mid), build(mid + 1, hi)),
      );
    }

    build(0, merges.length);
    return ends;
  }

  /// Inclusive bounds, in original document order. Preserve first-match
  /// behavior even for overlapping imported merges and anchors outside view.
  List<GridMerge> mergesIn(GridBounds bounds) {
    final found = <int>[];
    void visit(int lo, int hi) {
      if (lo >= hi) return;
      final mid = (lo + hi) ~/ 2;
      if (_mergeEnds[mid] < bounds.row) return;
      final id = _mergeOrder[mid], merge = merges[id];
      visit(lo, mid);
      if (merge.row > bounds.endRow) return;
      if (merge.endRow >= bounds.row &&
          merge.column <= bounds.endColumn &&
          merge.endColumn >= bounds.column) {
        found.add(id);
      }
      visit(mid + 1, hi);
    }

    visit(0, merges.length);
    found.sort();
    return [for (final id in found) merges[id]];
  }

  GridMerge? mergeAt(int row, int column) {
    if (merges.isEmpty) return null;
    if (merges.first.contains(row, column)) return merges.first;
    return mergesIn(GridBounds(row, column, row, column)).firstOrNull;
  }
}
