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
      final renderer = MemoryPdfRenderer();
      await setup(
        tester,
        const Size(393, 873),
        1,
        NativePdfScreen(
          backend: FakeDocumentBackend(NativeDocumentKind.pdf),
          renderer: renderer,
          launch: const EditorLaunch(create: true),
        ),
      );
      expect(renderer.opened, 1);
      expect(renderer.closed, isEmpty);
      await tester.tap(find.text('Чтение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Страницы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дублировать'));
      await tester.pumpAndSettle();
      expect(renderer.opened, 2);
      expect(renderer.closed, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(renderer.closed, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );
}

// No Android channel: the editor only needs the renderer contract.
class MemoryPdfRenderer implements PdfPageRenderer {
  int opened = 0;
  final closed = <int>[];
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  @override
  Future<int> open(Uint8List pdf) async => ++opened;
  @override
  Future<Uint8List> render(int session, int page, {int width = 1000}) async => image;
  @override
  Future<PdfOcrResult> recognize(int session, int page) async => (text: '', words: <PdfOcrWord>[]);
  @override
  Future<void> close(int session) async { closed.add(session); }
}
