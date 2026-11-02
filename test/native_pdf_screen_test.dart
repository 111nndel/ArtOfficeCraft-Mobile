import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';

void main() {
  testWidgets('PDF screen disables native actions on desktop', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NativePdfScreen()));
    expect(find.text('Rust недоступен'), findsOneWidget);
    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(
      buttons.any((b) => b.tooltip == 'Открыть PDF' && b.onPressed == null),
      isTrue,
    );
  });
}
