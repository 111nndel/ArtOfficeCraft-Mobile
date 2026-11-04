const gridMaxRows = 1048576;
const gridMaxColumns = 16384;

String gridColumnName(int column) {
  var value = column + 1;
  var result = '';
  while (value > 0) {
    result = String.fromCharCode(65 + (value - 1) % 26) + result;
    value = (value - 1) ~/ 26;
  }
  return result;
}

({int row, int column})? gridAddress(String text) {
  final match = RegExp(r'^\$?([A-Z]{1,3})\$?([1-9][0-9]{0,6})$')
      .firstMatch(text.trim().toUpperCase());
  if (match == null) return null;
  var column = 0;
  for (final c in match[1]!.codeUnits) {
    column = column * 26 + c - 64;
  }
  final row = int.parse(match[2]!);
  if (row > gridMaxRows || column > gridMaxColumns) return null;
  return (row: row - 1, column: column - 1);
}

/// Zero-based rectangle; bounds are validated again at the Rust boundary.
class GridWindow {
  const GridWindow(
    this.sheet,
    this.row,
    this.column, {
    this.rows = 64,
    this.columns = 16,
    this.overview = false,
  }) : rowIndices = null,
       columnIndices = null;
  GridWindow.visible(this.sheet, List<int> rowList, List<int> columnList)
    : overview = false,
      rowIndices = List.unmodifiable(rowList),
      columnIndices = List.unmodifiable(columnList),
      row = rowList.first,
      column = columnList.first,
      rows = rowList.last - rowList.first + 1,
      columns = columnList.last - columnList.first + 1;
  final int sheet, row, column, rows, columns;
  final bool overview;
  final List<int>? rowIndices, columnIndices;
  Iterable<int> get requestedRows =>
      rowIndices ?? List.generate(rows, (i) => row + i);
  Iterable<int> get requestedColumns =>
      columnIndices ?? List.generate(columns, (i) => column + i);
  bool contains(int r, int c) =>
      r >= row &&
      r < row + rows &&
      c >= column &&
      c < column + columns &&
      (rowIndices == null || rowIndices!.contains(r)) &&
      (columnIndices == null || columnIndices!.contains(c));
  bool covers(GridWindow other) =>
      overview == other.overview &&
      sheet == other.sheet &&
      other.requestedRows.every(
        (r) =>
            r >= row &&
            r < row + rows &&
            (rowIndices == null || rowIndices!.contains(r)),
      ) &&
      other.requestedColumns.every(
        (c) =>
            c >= column &&
            c < column + columns &&
            (columnIndices == null || columnIndices!.contains(c)),
      );
  GridWindow get buffered {
    if (overview) return this;
    if (rowIndices != null) return this;
    final height = (rows + 32).clamp(64, 128);
    final width = (columns + 8).clamp(16, 32);
    final r = (row - 16).clamp(0, gridMaxRows - height);
    final c = (column - 4).clamp(0, gridMaxColumns - width);
    return GridWindow(sheet, r, c, rows: height, columns: width);
  }

  Map<String, dynamic> request(String selected) => {
    'sheet': sheet,
    'row': row,
    'column': column,
    'rows': rows,
    'columns': columns,
    'selected': selected,
    if (overview) 'overview': true,
    if (rowIndices != null) 'rowIndices': rowIndices,
    if (columnIndices != null) 'columnIndices': columnIndices,
  };
}
