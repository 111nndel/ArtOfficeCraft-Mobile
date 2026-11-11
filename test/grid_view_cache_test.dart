import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/grid_view_cache.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/grid_layout.dart';

void main() {
  const style = {'fontSize': 11, 'fontName': 'Imported default', 'wrap': false};
  Map<String, dynamic> cell(String text) => {
    'input': text,
    'display': text,
    'style': style,
  };
  final layout = GridLayout.fromJson(null);

  test(
    'Returning to earlier rows/columns retains records and known empty styles',
    () {
      final cache = GridViewCache()..bind(Object(), 0);
      const first = GridWindow(0, 0, 0, rows: 4, columns: 4);
      const far = GridWindow(0, 100, 30, rows: 4, columns: 4);
      cache.put(first, {'A1': cell('first')}, {}, emptyStyle: style);
      cache.put(far, {'AE101': cell('far')}, {});
      expect(cache.coveringWindow(first), first);
      expect(cache.cells['A1']['input'], 'first');
      expect(cache.selectionAt('B2', layout), {
        'address': 'B2',
        'input': '',
        'display': '',
        'numeric': false,
        'formula': false,
        'style': style,
      });
      expect(cache.selectionAt('E5', layout), isNull);
      expect(cache.cellsFor(first).containsKey('AE101'), isFalse);
    },
  );
  test(
    'A new workbook version or active sheet never reuses old cell content',
    () {
      final cache = GridViewCache();
      final document = Object();
      cache.bind(document, 0);
      cache.put(
        const GridWindow(0, 0, 0),
        {'A1': cell('old')},
        {},
        emptyStyle: style,
      );
      cache.bind(document, 0);
      expect(cache.cells, isNotEmpty);
      cache.bind(document, 1);
      expect(cache.cells, isEmpty);
      cache.put(const GridWindow(1, 0, 0), {'A1': cell('other sheet')}, {});
      cache.bind(Object(), 1);
      expect(cache.cells, isEmpty);
      expect(cache.selectionAt('B2', layout), isNull);
    },
  );
  test(
    'Merged anchors outside a sparse rectangle keep their exact selection',
    () {
      final cache = GridViewCache()..bind(Object(), 0);
      cache.put(
        GridWindow.visible(0, [1, 3], [1, 3]),
        {'A1': cell('merged')},
        {},
        emptyStyle: style,
      );
      final merged = GridLayout(layout.rows, layout.columns, [
        const GridMerge(0, 0, 1, 2),
      ]);
      expect(cache.selectionAt('B2', merged)!['address'], 'A1');
      expect(cache.selectionAt('B2', merged)!['input'], 'merged');
      expect(
        cache.selectionAt('C3', layout),
        isNull,
      ); // A gap is not a fetched empty cell.
    },
  );
  test('Retention evicts least recently used windows and keeps an oversize active view', () {
    final cache = GridViewCache(maxWindows: 2, maxCells: 8, maxTextUnits: 1000)
      ..bind(Object(), 0);
    const a = GridWindow(0, 0, 0, rows: 2, columns: 2),
        b = GridWindow(0, 10, 0, rows: 2, columns: 2),
        c = GridWindow(0, 20, 0, rows: 2, columns: 2);
    cache.put(a, {'A1': cell('a')}, {});
    cache.put(b, {'A11': cell('b')}, {});
    cache.coveringWindow(a);
    cache.put(c, {'A21': cell('c')}, {});
    expect(cache.coveringWindow(b), isNull);
    expect(cache.coveringWindow(a), a);
    const big = GridWindow(0, 30, 0, rows: 20, columns: 20);
    cache.put(big, {'A31': cell('active')}, {});
    expect(cache.coveringWindow(a), isNull);
    expect(cache.coveringWindow(big), big);
  });
  test('Large text does not accumulate across retained regions', () {
    final cache = GridViewCache(maxTextUnits: 12)..bind(Object(), 0);
    cache.put(const GridWindow(0, 0, 0, rows: 1, columns: 1), {
      'A1': cell('12345'),
    }, {});
    cache.put(const GridWindow(0, 1, 0, rows: 1, columns: 1), {
      'A2': cell('67890'),
    }, {});
    expect(cache.cells.keys, ['A2']);
  });
  test('Read-ahead skips hidden runs and respects native window bounds', () {
    final hidden = GridLayout(
      GridAxis(gridMaxRows, 20, [
        [1, 999990, 0],
      ]),
      GridAxis(gridMaxColumns, 64),
      const [],
    );
    final visible = GridWindow.visible(0, [0, 999991, 999992], [0, 1]);
    final ahead = prefetchGridWindow(visible, hidden);
    expect(ahead.covers(visible), isTrue);
    expect(ahead.rowIndices!.length, lessThan(40));
    expect(ahead.rowIndices, isNot(contains(5000)));
    final edge = prefetchGridWindow(
      const GridWindow(
        0,
        gridMaxRows - 1,
        gridMaxColumns - 1,
        rows: 1,
        columns: 1,
      ),
      layout,
    );
    expect(edge.contains(gridMaxRows - 1, gridMaxColumns - 1), isTrue);
    expect(edge.row + edge.rows, lessThanOrEqualTo(gridMaxRows));
    expect(edge.column + edge.columns, lessThanOrEqualTo(gridMaxColumns));
  });
}
