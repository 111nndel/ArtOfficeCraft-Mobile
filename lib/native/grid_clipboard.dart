import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../platform/system_clipboard.dart';

import 'document_backend.dart';
import 'grid_selection.dart';

/// Exactly one bounded rich snapshot per app session. Only selected TSV text
/// and an opaque identity token are placed on a capable system clipboard.
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
        text.length > maxText ||
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
  GridClipboard(this.system);
  final SystemClipboard system;
  bool get supportsFormatting => system.supportsIdentity;
  GridClip? _current;
  GridClip? get current => _current;
  Future<void> _queue = Future.value();
  int _generation = 0;

  void clearLocal() {
    _generation++;
    _current = null;
  }

  Future<T> _serialize<T>(Future<T> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> write(GridClip entry) {
    final generation = _generation;
    return _serialize(() async {
      await system.write((text: entry.text, token: entry.token));
      if (generation == _generation) {
        _current = supportsFormatting ? entry : null;
      }
    });
  }

  Future<({String text, GridClip? rich})?> read() => _serialize(() async {
    final value = await system.read();
    if (value == null) {
      _current = null;
      return null;
    }
    final text = value.text;
    if (text.length > GridClip.maxText ||
        utf8.encode(text).length > GridClip.maxText) {
      _current = null;
      throw const FormatException('Текст буфера обмена превышает 256 КиБ');
    }
    final rich = _current;
    if (rich == null || value.token != rich.token || text != rich.text) {
      _current = null;
      return text.isEmpty ? null : (text: text, rich: null);
    }
    return (text: text, rich: rich);
  });
}
