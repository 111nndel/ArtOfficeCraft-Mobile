import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 393.0, 800.0]) {
    testWidgets('Caption, nested pane, return and retained canvas at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = TextEditingController(text: 'Не терять');
      addTearDown(draft.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: OfficeTheme.build(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: TextField(key: const Key('canvas'), controller: draft),
                ),
                EditorToolPanel(
                  color: Colors.green,
                  sections: [
                    EditorSection('Главная', [
                      EditorTool(
                        'Абзац',
                        Icons.format_align_left,
                        children: [
                          EditorTool(
                            'Отступы',
                            Icons.format_indent_increase,
                            builder: (_) => const TextField(
                              key: Key('indent'),
                              decoration: InputDecoration(labelText: 'Отступ'),
                            ),
                          ),
                        ],
                      ),
                      for (var i = 0; i < 20; i++)
                        EditorTool('Команда $i', Icons.edit, onPressed: () {}),
                    ]),
                    const EditorSection('Вид', [
                      EditorTool('Масштаб', Icons.zoom_in, pending: true),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      final field = tester.state(find.byKey(const Key('canvas')));
      final caption = find.byKey(const Key('tool-section-caption'));
      expect(tester.getSize(caption).height, greaterThanOrEqualTo(52));
      // Hit the actual letters, not the expand arrow.
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-menu-1')), findsOneWidget);
      await tester.tap(find.text('Вид').last);
      await tester.pumpAndSettle();
      expect(find.text('Масштаб'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tool-section-caption')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-menu-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Абзац'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отступы'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('indent')), '12');
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Развернуть инструменты'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('indent')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '12',
      );
      await tester.tap(find.byTooltip('Назад к инструментам'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад к инструментам'));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('pane-0'));
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      final offset = scroll.position.pixels;
      await tester.tap(caption);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(caption);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-menu-0')));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, offset);
      expect(tester.state(find.byKey(const Key('canvas'))), same(field));
      expect(draft.text, 'Не терять');
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
