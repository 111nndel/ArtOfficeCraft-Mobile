import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_history.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List state(int id, int size) => Uint8List(size)..fillRange(0, size, id);
void main() {
  test('Undo/redo share the byte budget, preserve nearest states, and clear branches', () {
    final history = DocumentHistory(byteBudget: 16, stepBudget: 5);
    history.push(state(1, 8));
    history.push(state(2, 8));
    expect(history.undo(state(3, 12)).first, 2);
    expect(history.retainedBytes, lessThanOrEqualTo(16));
    expect(history.canUndo, isFalse);
    expect(history.redo(state(2, 8)).first, 3);
    expect(history.undoTarget!.first, 2);
    history.undo(state(3, 12));
    history.push(state(4, 4));
    expect(history.canRedo, isFalse);
    expect(history.retainedBytes, lessThanOrEqualTo(16));
  });
  test('Oversized current file is not retained by redo; history owns immutable snapshots', () {
    final history = DocumentHistory(byteBudget: 16);
    final original = state(1, 8);
    history.push(original);
    original[0] = 99;
    final restored = history.undo(state(2, 17));
    expect(restored.first, 1);
    expect(history.canRedo, isFalse);
    expect(() => restored[0] = 2, throwsUnsupportedError);
    expect(history.retainedBytes, 0);
  });
  test(
    'The step limit covers both directions and a new edit drops future steps',
    () {
      final history = DocumentHistory(byteBudget: 100, stepBudget: 3);
      for (var i = 1; i <= 7; i++) {
        history.push(state(i, 1));
      }
      expect(history.retainedSteps, 3);
      final a = history.undo(state(8, 1));
      final b = history.undo(a);
      expect(b.first, 6);
      expect(history.retainedSteps, lessThanOrEqualTo(3));
      expect(history.redo(b).first, 7);
      history.push(state(9, 1));
      expect(history.canRedo, isFalse);
    },
  );
}
