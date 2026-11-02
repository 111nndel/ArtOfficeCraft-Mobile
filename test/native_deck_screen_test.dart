import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';

void main() {
  testWidgets('DeckCraft screen disables native actions outside Android', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NativeDeckScreen()));
    expect(find.text('Rust недоступен'), findsOneWidget);
    final controls = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(
      controls.any((v) => v.tooltip == 'Открыть PPTX' && v.onPressed == null),
      isTrue,
    );
  });
}
