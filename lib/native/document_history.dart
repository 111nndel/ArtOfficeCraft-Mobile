import 'dart:typed_data';

/// Bounded immutable snapshots; failed native operations never enter the history.
class DocumentHistory {
  final List<Uint8List> _undo = [], _redo = [];
  static const maxBytes = 24 * 1024 * 1024;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void push(Uint8List bytes) {
    _redo.clear();
    if (bytes.length > maxBytes) {
      _undo.clear();
      return;
    }
    _undo.add(bytes);
    while (_undo.length > 10 ||
        _undo.fold<int>(0, (n, b) => n + b.length) > maxBytes) {
      _undo.removeAt(0);
    }
  }

  Uint8List undo(Uint8List current) {
    final value = _undo.removeLast();
    _redo.add(current);
    return value;
  }

  Uint8List redo(Uint8List current) {
    final value = _redo.removeLast();
    _undo.add(current);
    return value;
  }
}
