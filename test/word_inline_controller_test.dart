import 'package:artofficecraft_mobile/native/word_inline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Inline draft preserves styled Unicode runs during typing and IME composition',
    (tester) async {
      final controller = WordInlineController();
      addTearDown(controller.dispose);
      controller.load({
        'text': 'A😀 хвост',
        'runs': [
          {'text': 'A😀 ', 'bold': true},
          {'text': 'хвост', 'italic': true},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );
      controller.value = const TextEditingValue(
        text: 'A😀 новый хвост',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 4, end: 9),
      );
      await tester.pump();
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: true,
      );
      expect(span.toPlainText(), 'A😀 новый хвост');
      final children = span.children!.cast<TextSpan>();
      expect(children.first.style!.fontWeight, FontWeight.bold);
      expect(children.last.style!.fontStyle, FontStyle.italic);
      expect(
        children.any((s) => s.style!.decoration == TextDecoration.underline),
        isTrue,
      );
      expect(controller.value.composing, const TextRange(start: 4, end: 9));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      expect(controller.propertyAtSelection('bold'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
