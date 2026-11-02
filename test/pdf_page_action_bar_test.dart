import 'package:artofficecraft_mobile/native/pdf_page_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PDF actions remain usable on narrow 320 dp screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PdfPageActionBar(
              selected: 0,
              pageCount: 3,
              busy: false,
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Страница 1 из 3 · действия листаются вбок'),
      findsOneWidget,
    );
    final earlier = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Раньше'),
    );
    expect(earlier.onPressed, isNull);
    final rotate = find.widgetWithText(OutlinedButton, 'Влево');
    await tester.ensureVisible(rotate);
    await tester.pumpAndSettle();
    await tester.tap(rotate);
    expect(actions, <String>['rotate_ccw']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF action buttons disabled while busy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfPageActionBar(
            selected: 0,
            pageCount: 1,
            busy: true,
            onAction: (_) {},
          ),
        ),
      ),
    );
    final buttons = tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(buttons.length, greaterThanOrEqualTo(4));
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    await tester.drag(find.byType(ListView), const Offset(-900, 0));
    await tester.pumpAndSettle();
    final delete = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Удалить'),
    );
    expect(delete.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
