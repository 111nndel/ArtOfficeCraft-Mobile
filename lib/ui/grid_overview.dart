import 'package:flutter/material.dart';

import '../native/grid_layout.dart';
import '../native/grid_window.dart';

/// Bounded, non-editing overview. Fine editing uses the normal cell viewport.
/// Paint sparse native records instead of mounting thousands of text fields.
class GridOverviewPainter extends CustomPainter {
  GridOverviewPainter(this.layout, this.cells, this.selected);
  final GridLayout layout;
  final Map<String, dynamic> cells;
  final String selected;

  static Color? rgb(dynamic value) {
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
  }

  Rect cellRect(int row, int column) {
    final merge = layout.mergeAt(row, column);
    return Rect.fromLTRB(
      layout.columns.offset(merge?.column ?? column),
      layout.rows.offset(merge?.row ?? row),
      layout.columns.offset((merge?.endColumn ?? column) + 1),
      layout.rows.offset((merge?.endRow ?? row) + 1),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint(), line = Paint()..style = PaintingStyle.stroke;
    final text = TextPainter(textDirection: TextDirection.ltr);
    try {
      for (final entry in cells.entries) {
        final at = gridAddress(entry.key);
        if (at == null || entry.value is! Map) continue;
        final merge = layout.mergeAt(at.row, at.column);
        if (merge != null &&
            (at.row != merge.row || at.column != merge.column)) {
          continue;
        }
        final item = entry.value as Map;
        final rect = cellRect(at.row, at.column);
        if (rect.isEmpty) continue;
        final style = item['style'] as Map? ?? const {};
        fill.color = rgb(style['fill']) ?? Colors.white;
        canvas.drawRect(rect, fill);
        final borders = style['borders'] as Map? ?? const {};
        for (final edge in ['left', 'right', 'top', 'bottom']) {
          final border = borders[edge] as Map? ?? const {};
          final width = (border['width'] as num?)?.toDouble() ?? 0;
          if (width <= 0 && !layout.showGridlines) continue;
          line.color = width > 0
              ? rgb(border['color']) ?? Colors.black
              : const Color(0xffe5e9ef);
          line.strokeWidth = width > 0 ? width.clamp(.3, 6).toDouble() : .7;
          final (a, b) = switch (edge) {
            'left' => (rect.topLeft, rect.bottomLeft),
            'right' => (rect.topRight, rect.bottomRight),
            'top' => (rect.topLeft, rect.topRight),
            _ => (rect.bottomLeft, rect.bottomRight),
          };
          canvas.drawLine(a, b, line);
        }
        final value = item['display']?.toString() ?? '';
        if (value.isEmpty || rect.width <= 6) continue;
        final numeric = item['numeric'] == true;
        final align = switch (style['align']) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          'left' => TextAlign.left,
          _ => numeric ? TextAlign.right : TextAlign.left,
        };
        text.textAlign = align;
        text.maxLines = style['wrap'] == true ? null : 1;
        text.text = TextSpan(
          text: value,
          style: TextStyle(
            fontSize: ((style['fontSize'] as num?)?.toDouble() ?? 11) * 4 / 3,
            height: 1.1,
            color: rgb(style['color']) ?? const Color(0xff172634),
            fontFamily: style['fontName'] as String?,
            fontWeight: style['bold'] == true
                ? FontWeight.bold
                : FontWeight.normal,
            fontStyle: style['italic'] == true
                ? FontStyle.italic
                : FontStyle.normal,
            decoration: TextDecoration.combine([
              if (style['underline'] == true) TextDecoration.underline,
              if (style['strike'] == true) TextDecoration.lineThrough,
            ]),
          ),
        );
        final available = rect.width - 6;
        text.layout(
          maxWidth: style['wrap'] == true ? available : double.infinity,
        );
        final shrink =
            style['shrink'] == true &&
                style['wrap'] != true &&
                text.width > available
            ? available / text.width
            : 1.0;
        final width = text.width * shrink, height = text.height * shrink;
        final x =
            rect.left +
            3 +
            (align == TextAlign.right
                ? available - width
                : align == TextAlign.center
                ? (available - width) / 2
                : 0);
        final y =
            rect.top +
            switch (style['verticalAlign']) {
              'top' => 0.0,
              'center' => (rect.height - height) / 2,
              _ => rect.height - height,
            };
        canvas.save();
        canvas.clipRect(rect.deflate(1));
        canvas.translate(x, y);
        canvas.scale(shrink);
        text.paint(canvas, Offset.zero);
        canvas.restore();
      }
      final at = gridAddress(selected);
      if (at != null) {
        line
          ..color = const Color(0xff188458)
          ..strokeWidth = 2;
        canvas.drawRect(cellRect(at.row, at.column), line);
      }
    } finally {
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(GridOverviewPainter old) =>
      !identical(layout, old.layout) ||
      !identical(cells, old.cells) ||
      selected != old.selected;
}
