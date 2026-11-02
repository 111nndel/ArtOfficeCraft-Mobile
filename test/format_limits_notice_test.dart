import 'package:artofficecraft_mobile/native/format_limits_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Format warning is compact but details remain accessible at 200%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ListView(
                children: const [
                  FormatLimitsNotice(
                    summary: 'PPTX · упрощённый предпросмотр',
                    details: 'Темы и сложные графические элементы пока не поддерживаются.',
                  ),
                  SizedBox(height: 300, child: Text('Документ')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PPTX · упрощённый предпросмотр'), findsOneWidget);
      expect(
        find.text(
          'Темы и сложные графические элементы пока не поддерживаются.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('PPTX · упрощённый предпросмотр'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Темы и сложные графические элементы пока не поддерживаются.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
