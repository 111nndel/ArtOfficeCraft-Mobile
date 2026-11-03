import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';

void main() {
  testWidgets('WordCraft reports unavailable native operations', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NativeWordScreen()));
    expect(find.textContaining('Rust недоступен'), findsWidgets);
    final menu = tester.widget<EditorFileMenu>(find.byType(EditorFileMenu));
    expect(
      menu.commands.firstWhere((c) => c.label == 'Открыть DOCX').onPressed,
      isNull,
    );
  });
}
