import 'dart:typed_data';

import 'document_backend.dart' show immutableDocumentBytes;

/// Undo and redo share one byte/step budget, excluding the current document.
/// A failed native restore never enters or consumes this history.
class DocumentHistory {
  DocumentHistory({this.byteBudget = maxBytes, this.stepBudget = 10}) {
    if (byteBudget < 1 || stepBudget < 1) {
      throw ArgumentError('History budget must be positive');
    }
  }
  final int byteBudget, stepBudget;
  final List<Uint8List> _undo = [], _redo = [];
  static const maxBytes = 24 * 1024 * 1024;
  int get retainedBytes => [..._undo, ..._redo].fold(0, (n, b) => n + b.length);
  int get retainedSteps => _undo.length + _redo.length;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  Uint8List? get undoTarget => _undo.isEmpty ? null : _undo.last;
  Uint8List? get redoTarget => _redo.isEmpty ? null : _redo.last;
  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void push(Uint8List bytes) {
    _redo.clear();
    _record(_undo, bytes);
  }

  void _record(List<Uint8List> target, Uint8List bytes) {
    if (bytes.length > byteBudget) {
      target.clear();
      return;
    }
    target.add(immutableDocumentBytes(bytes));
    final other = identical(target, _undo) ? _redo : _undo;
    while (retainedBytes > byteBudget || retainedSteps > stepBudget) {
      if (other.isNotEmpty) {
        other.removeAt(0);
      } else {
        target.removeAt(0);
      }
    }
  }

  Uint8List undo(Uint8List current) {
    if (_undo.isEmpty) throw StateError('No undo state');
    final value = _undo.removeLast();
    _record(_redo, current);
    return value;
  }

  Uint8List redo(Uint8List current) {
    if (_redo.isEmpty) throw StateError('No redo state');
    final value = _redo.removeLast();
    _record(_undo, current);
    return value;
  }
}
