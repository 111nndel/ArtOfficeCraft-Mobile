import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';

void main() {
  testWidgets('WordCraft UI reports missing Android library on desktop',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NativeWordScreen()));
    expect(find.textContaining('Rust недоступен'), findsOneWidget);
    expect(find.byTooltip('Открыть DOCX'), findsOneWidget);
    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons.any((button) =>
        button.tooltip == 'Открыть DOCX' && button.onPressed == null), isTrue);
  });
}
