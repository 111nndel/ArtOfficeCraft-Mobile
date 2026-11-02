import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';

void main() {
  testWidgets('Excel screen clearly disables native operations on desktop', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:NativeGridScreen()));
    expect(find.text('Rust недоступен'),findsOneWidget);
    final buttons=tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons.any((b)=>b.tooltip=='Открыть XLSX' && b.onPressed==null),isTrue);
  });
}
