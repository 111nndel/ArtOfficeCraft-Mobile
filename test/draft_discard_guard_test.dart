import 'package:artofficecraft_mobile/native/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'A failed draft removal keeps the editor open and allows a retry',
    (tester) async {
      var fail = true, discards = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => UnsavedChangesGuard(
                      dirty: true,
                      busy: false,
                      onDiscard: () async {
                        discards++;
                        if (fail) throw StateError('Storage unavailable');
                      },
                      child: Scaffold(
                        appBar: AppBar(title: const Text('Editor')),
                        body: const Text('Unsaved draft'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выйти без сохранения'));
      await tester.pumpAndSettle();
      expect(find.text('Editor'), findsOneWidget);
      expect(discards, 1);
      fail = false;
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выйти без сохранения'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(discards, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
