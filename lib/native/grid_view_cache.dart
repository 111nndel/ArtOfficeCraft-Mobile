import 'grid_layout.dart';
import 'grid_window.dart';

/// Recent read-only regions of one immutable workbook/sheet. Edits, undo and
/// file/sheet changes bind a new snapshot before any records are published.
class GridViewCache {
  GridViewCache({
    this.maxWindows = 8,
    this.maxCells = 32768,
    this.maxTextUnits = 2 * 1024 * 1024,
  });
  final int maxWindows, maxCells, maxTextUnits;
  Object? _document;
  int? _sheet;
  final _entries = <_Region>[];
  Map<String, dynamic> _cells = const {};
  Map<String, dynamic>? _emptyStyle;
  Map<String, dynamic> get cells => _cells;

  bool isBoundTo(Object document, int sheet) =>
      identical(_document, document) && _sheet == sheet;

  void bind(Object document, int sheet) {
    if (!isBoundTo(document, sheet)) {
      _entries.clear();
      _cells = const {};
      _emptyStyle = null;
    }
    _document = document;
    _sheet = sheet;
  }

  void put(
    GridWindow window,
    Map<String, dynamic> cells,
    Map<String, dynamic> selection, {
    Map<String, dynamic>? emptyStyle,
  }) {
    if (_sheet != window.sheet) throw StateError('Wrong cached sheet');
    if (emptyStyle != null) _emptyStyle = Map.unmodifiable(emptyStyle);
    _entries.removeWhere(
      (e) => e.window.covers(window) && window.covers(e.window),
    );
    _entries.add(_Region(window, cells, selection));
    int cost(bool text) =>
        _entries.fold(0, (n, e) => n + (text ? e.textUnits : e.cellCount));
    // Keep the active region even when a zoomed-out view alone exceeds the
    // retention budget. Never sample or truncate the visible worksheet.
    while (_entries.length > 1 &&
        (_entries.length > maxWindows ||
            cost(false) > maxCells ||
            cost(true) > maxTextUnits)) {
      _entries.removeAt(0);
    }
    _cells = Map.unmodifiable({for (final entry in _entries) ...entry.cells});
  }

  _Region? _cover(GridWindow window) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      if (entry.window.covers(window)) {
        _entries.removeAt(i);
        _entries.add(entry);
        return entry;
      }
    }
    return null;
  }

  GridWindow? coveringWindow(GridWindow window) => _cover(window)?.window;

  bool contains(int row, int column) =>
      _entries.any((entry) => entry.window.contains(row, column));

  /// Compact painting normally needs one prefetched region, not every region
  /// retained for returning to earlier rows/columns.
  Map<String, dynamic> cellsFor(GridWindow window) {
    final hit = _cover(window);
    if (hit != null) return hit.cells;
    final result = <String, dynamic>{};
    for (final entry in _entries) {
      final at = entry.window;
      if (at.sheet == window.sheet &&
          at.row < window.row + window.rows &&
          window.row < at.row + at.rows &&
          at.column < window.column + window.columns &&
          window.column < at.column + at.columns) {
        result.addAll(entry.cells);
      }
      final selected = entry.selected;
      if (selected != null) result[selected] = entry.cells[selected];
    }
    return result;
  }

  Map<String, dynamic>? selectionAt(String address, GridLayout layout) {
    final at = gridAddress(address);
    if (at == null) return null;
    final merge = layout.mergeAt(at.row, at.column);
    final row = merge?.row ?? at.row, column = merge?.column ?? at.column;
    final canonical = '${gridColumnName(column)}${row + 1}';
    final record = _cells[canonical];
    if (record is Map) {
      return {...Map<String, dynamic>.from(record), 'address': canonical};
    }
    // The native window omits only genuinely empty style-0 cells. Its exact
    // default style is supplied once, so local selection preserves formatting.
    if (_emptyStyle == null || !contains(row, column)) {
      return null;
    }
    return {
      'address': canonical,
      'input': '',
      'display': '',
      'numeric': false,
      'formula': false,
      'style': _emptyStyle,
    };
  }
}

class _Region {
  _Region(
    this.window,
    Map<String, dynamic> source,
    Map<String, dynamic> selection,
  ) : selected = selection['address'] as String?,
      cells = Map.unmodifiable({
        ...source,
        if (selection['address'] is String)
          selection['address'] as String: selection,
      }) {
    final positions =
        window.requestedRows.length * window.requestedColumns.length;
    cellCount = positions > cells.length ? positions : cells.length;
    textUnits = 0;
    for (final record in cells.values) {
      if (record is! Map) continue;
      for (final key in ['input', 'display']) {
        final value = record[key];
        if (value is String) textUnits += value.length;
      }
    }
  }
  final GridWindow window;
  final String? selected;
  final Map<String, dynamic> cells;
  late final int cellCount;
  late int textUnits;
}

/// Read ahead using actual axis geometry, including gaps of hidden rows/columns.
/// The existing native request bounds still apply; oversize padding is skipped.
GridWindow prefetchGridWindow(GridWindow visible, GridLayout layout) {
  final rows = layout.rows.visible(
    layout.rows.offset(visible.row),
    layout.rows.offset(visible.row + visible.rows),
    buffer: 16,
  );
  final columns = layout.columns.visible(
    layout.columns.offset(visible.column),
    layout.columns.offset(visible.column + visible.columns),
    buffer: 8,
  );
  if (rows.isEmpty ||
      columns.isEmpty ||
      rows.length > 8192 ||
      columns.length > 2048 ||
      rows.length * columns.length > 262144) {
    return visible;
  }
  return GridWindow.visible(visible.sheet, rows, columns);
}
