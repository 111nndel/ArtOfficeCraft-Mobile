import 'dart:convert';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show FakeDocumentBackend, setup;

void main() {
  testWidgets(
    'Replacing a PDF render session closes the old document and disposes the current one',
    (tester) async {
      const channel = MethodChannel('artofficecraft/pdf_renderer');
      final closed = <int>[];
      var opened = 0;
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'openDocument') {
              return {'session': ++opened, 'pageCount': 1};
            }
            if (call.method == 'renderPage') return Uint8List.fromList(image);
            if (call.method == 'closeDocument') {
              closed.add((call.arguments as Map)['session'] as int);
              return null;
            }
            throw StateError(call.method);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativePdfScreen(
          backend: FakeDocumentBackend(NativeDocumentKind.pdf),
          renderer: PdfPageRenderer(allowNonAndroidForTesting: true),
          launch: const EditorLaunch(create: true),
        ),
      );
      expect(opened, 1);
      expect(closed, isEmpty);
      await tester.tap(find.text('Чтение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Страницы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дублировать'));
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(closed, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(closed, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );
}
