import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'document_backend.dart';
import 'grid_selection.dart';

/// Exactly one bounded rich snapshot per app session. Only selected TSV text
/// and an opaque identity token are placed on Android's system clipboard.
class GridClip {
  GridClip(Uint8List bytes, this.sheet, Map<String, dynamic> info)
    : source = _snapshot(bytes, sheet),
      range =
          GridSelection.parse(info['range'] as String? ?? '') ??
          (throw const FormatException('Некорректный диапазон буфера')),
      text = info['text'] as String? ?? '',
      token = _token() {
    if (bytes.length > maxSource ||
        range.cellCount > GridSelection.maxCells ||
        utf8.encode(text).length > maxText ||
        info['rows'] != rows ||
        info['columns'] != columns) {
      throw const FormatException(
        'Буфер обмена превышает ограничения мобильного редактора',
      );
    }
  }
  static Uint8List _snapshot(Uint8List bytes, int sheet) {
    if (bytes.length > maxSource || sheet < 0) {
      throw const FormatException('Некорректный источник буфера обмена');
    }
    return immutableDocumentBytes(bytes);
  }

  static const maxSource = 24 * 1024 * 1024, maxText = 256 * 1024;
  final Uint8List source;
  final int sheet;
  final GridSelection range;
  final String text, token;
  int get rows => range.endRow - range.row + 1;
  int get columns => range.endColumn - range.column + 1;
  static String _token() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

class GridClipboard {
  static const channel = MethodChannel('artofficecraft/grid_clipboard');
  static GridClip? _current;
  static GridClip? get current => _current;
  static void clearLocal() => _current = null;
  static Future<void> write(GridClip entry) async {
    await channel.invokeMethod<void>('write', {
      'text': entry.text,
      'token': entry.token,
    });
    _current = entry;
  }

  static Future<({String text, GridClip? rich})?> read() async {
    final value = await channel.invokeMapMethod<String, dynamic>('read');
    final text = value?['text'];
    if (text is! String) {
      clearLocal();
      return null;
    }
    if (utf8.encode(text).length > GridClip.maxText) {
      clearLocal();
      throw const FormatException('Текст буфера обмена превышает 256 КиБ');
    }
    final rich = _current;
    if (rich == null || value?['token'] != rich.token || text != rich.text) {
      clearLocal();
      return text.isEmpty ? null : (text: text, rich: null);
    }
    return (text: text, rich: rich);
  }
}
