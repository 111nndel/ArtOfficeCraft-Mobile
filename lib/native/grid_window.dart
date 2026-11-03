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
  });
  final int sheet, row, column, rows, columns;
  bool contains(int r, int c) =>
      r >= row && r < row + rows && c >= column && c < column + columns;
  bool covers(GridWindow other) =>
      sheet == other.sheet &&
      contains(other.row, other.column) &&
      contains(other.row + other.rows - 1, other.column + other.columns - 1);
  GridWindow get buffered {
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
  };
}
