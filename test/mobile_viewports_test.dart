import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';

import 'loaded_editors_test.dart' show FakeDocumentBackend;

import 'dart:convert';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final pixel = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);
Future<void> pinch(WidgetTester tester, Finder target) async {
  final center = tester.getCenter(target);
  final a = await tester.createGesture(pointer: 1);
  final b = await tester.createGesture(pointer: 2);
  await a.down(center - const Offset(35, 0));
  await b.down(center + const Offset(35, 0));
  await tester.pump();
  for (var step = 1; step <= 5; step++) {
    final distance = 35.0 + 11 * step;
    await a.moveTo(center - Offset(distance, 0));
    await b.moveTo(center + Offset(distance, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Sheet pinch enlarges cells; panning builds distant rows and taps still work',
    (tester) async {
      final key = GlobalKey<SheetViewportState>();
      var chosen = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 420,
              child: SheetViewport(
                key: key,
                width: 900,
                rowCount: 55,
                header: const ColoredBox(
                  color: Colors.white,
                  child: Text('A B C'),
                ),
                rowBuilder: (context, row) => InkWell(
                  key: ValueKey('row-$row'),
                  onTap: () => chosen = row,
                  child: Text('row $row'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('row-54')), findsNothing);
      await pinch(tester, find.byKey(const Key('sheet-viewport')));
      expect(key.currentState!.zoom, greaterThan(1.5));
      final rowBounds = tester.getRect(find.byKey(const ValueKey('row-3')));
      final viewportBounds = tester.getRect(
        find.byKey(const Key('sheet-viewport')),
      );
      final touch = Offset(viewportBounds.left + 40, rowBounds.center.dy);
      expect(viewportBounds.contains(touch), isTrue);
      await tester.tapAt(touch);
      await tester.pump();
      expect(chosen, 3);
      key.currentState!.reset();
      key.currentState!.setZoom(1.5);
      await tester.pumpAndSettle();
      final firstRow = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(
        tester
            .getRect(find.byKey(const Key('sheet-viewport')))
            .contains(Offset(firstRow.left + 40, firstRow.center.dy)),
        isTrue,
      );
      key.currentState!.setZoom(1);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('sheet-viewport')),
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-54')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Tall PDF opens at full width; pinch/pan reach beyond viewport; fit page is available',
    (tester) async {
      final key = GlobalKey<PdfViewportState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 300,
                child: PdfViewport(
                  key: key,
                  image: Future.value(pixel),
                  pageWidth: 612,
                  pageHeight: 1400,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        key.currentState!.transform.value.getMaxScaleOnAxis(),
        closeTo(304 / 612, .001),
      );
      expect(
        tester.getSize(find.byKey(const Key('pdf-viewport'))),
        const Size(320, 300),
      );
      await pinch(tester, find.byKey(const Key('pdf-viewport')));
      final zoomed = key.currentState!.transform.value.getMaxScaleOnAxis();
      expect(zoomed, greaterThan(304 / 612));
      await tester.drag(
        find.byKey(const Key('pdf-viewport')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.transform.value.storage[13], lessThan(0));
      key.currentState!.fitPage();
      await tester.pumpAndSettle();
      expect(
        key.currentState!.transform.value.getMaxScaleOnAxis() * 1400,
        lessThanOrEqualTo(284.01),
      );
      key.currentState!.fitWidth();
      await tester.pumpAndSettle();
      expect(
        key.currentState!.transform.value.getMaxScaleOnAxis(),
        closeTo(304 / 612, .001),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Expanded sheet tools keep the Android status area clear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24),
            viewPadding: const EdgeInsets.only(top: 24),
          ),
          child: child!,
        ),
        home: NativeGridScreen(
          backend: FakeDocumentBackend(NativeDocumentKind.grid),
          launch: const EditorLaunch(create: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Развернуть инструменты'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('sheet-viewport'))).dy,
      greaterThanOrEqualTo(24),
    );
    expect(tester.takeException(), isNull);
  });
}
