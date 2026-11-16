import 'package:artofficecraft_mobile/native/word_inline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

void main() {
  testWidgets(
    'An empty paragraph inherits mark formatting before its first character',
    (tester) async {
      final controller = WordInlineController();
      addTearDown(controller.dispose);
      controller.load({
        'text': '',
        'emptyStyle': {'bold': true, 'size': 18, 'color': '#3565CA'},
      });
      expect(controller.propertyAtSelection('bold'), isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox).first);
      expect(
        controller
            .buildTextSpan(context: context, withComposing: false)
            .style!
            .fontSize,
        closeTo(18 * 1.33, .001),
      );
      controller.text = '😀';
      final span = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      final style = span.children!.cast<TextSpan>().single.style!;
      expect(style.fontWeight, FontWeight.bold);
      expect(style.color, const Color(0xff3565CA));
      expect(style.fontSize, closeTo(18 * 1.33, .001));
    },
  );
  testWidgets(
    'Long Unicode paragraph load preserves per-character formatting with shared run styles',
    (tester) async {
      final controller = WordInlineController();
      addTearDown(controller.dispose);
      final runs = [
        for (var i = 0; i < 4; i++)
          {
            'text': 'Абзац 😀 ' * 256,
            'bold': i.isEven,
            'italic': i.isOdd,
            'color': i.isEven ? '#3565CA' : '#147553',
            'size': 16,
          },
      ];
      final text = runs.map((r) => r['text'] as String).join();
      final block = {'text': text, 'runs': runs};
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox).first);
      final times = {
        'previousStyleExpansion': <int>[],
        'currentFullLoad': <int>[],
      };
      final watch = Stopwatch();
      for (var sample = 0; sample < 30; sample++) {
        List<TextStyle>? expected;
        for (final mode
            in sample.isEven ? times.keys : times.keys.toList().reversed) {
          watch
            ..reset()
            ..start();
          if (mode == 'previousStyleExpansion') {
            expected = [
              for (final run in runs)
                for (var i = 0; i < (run['text'] as String).length; i++)
                  WordInlineController.runStyle(run),
            ];
          } else {
            controller.load(block);
          }
          times[mode]!.add(watch.elapsedMicroseconds);
        }
        final span = controller.buildTextSpan(
          context: context,
          withComposing: false,
        );
        expect(span.toPlainText(), text);
        final actual = [
          for (final child in span.children!.cast<TextSpan>())
            ...List.filled(child.text!.length, child.style!),
        ];
        expect(actual, expected);
        expect(controller.selection.extentOffset, text.length);
      }
      double median(List<int> values) {
        final sorted = [...values]..sort();
        return (sorted[14] + sorted[15]) / 2;
      }

      debugPrint(
        'WORD_INLINE_BENCHMARK ${jsonEncode({
          'scope': 'Flutter debug Linux; style expansion versus full paragraph load; not Android FPS',
          'utf16Units': text.length,
          'runs': runs.length,
          'equalStyles': true,
          'medianUs': {for (final e in times.entries) e.key: median(e.value)},
        })}',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Inline draft preserves styled Unicode runs during typing and IME composition',
    (tester) async {
      final controller = WordInlineController();
      addTearDown(controller.dispose);
      controller.load({
        'text': 'A😀 хвост',
        'runs': [
          {'text': 'A😀 ', 'bold': true, 'color': '#3565CA'},
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
      expect(children.first.style!.color, const Color(0xff3565ca));
      expect(children.last.style!.color, isNull);
      expect(WordInlineController.textColor('auto'), isNull);
      expect(WordInlineController.textColor('#bad'), isNull);
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
