import 'package:artofficecraft_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Compact home labels are truthful on a 320 dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(toggleTheme: () {}, theme: ThemeMode.system),
      ),
    );
    expect(find.text('Создать файл'), findsOneWidget);
    expect(find.text('Рабочие пространства'), findsNothing);
    expect(find.textContaining('Настоящие файлы Office ещё'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
