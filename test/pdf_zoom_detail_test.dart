import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/ui/page_reading.dart';
import 'package:artofficecraft_mobile/ui/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<void> settleDetail(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Widget detailPage(
  Future<Uint8List> preview,
  PdfTileRaster render, {
  Rect viewport = const Rect.fromLTWH(0, 0, 300, 400),
  double density = 3,
  Object identity = 'page',
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 300,
        height: 400,
        child: PdfPageImage(
          image: preview,
          pageIdentity: identity,
          pageSize: const Size(600, 800),
          view: (viewport: viewport, pixelRatio: density),
          renderTile: render,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'single-page zoom requests physical-resolution crops and keeps the viewport',
    (tester) async {
      tester.view.physicalSize = const Size(960, 1440);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<PdfViewportState>();
      final calls = <PdfPageTile>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 400,
              child: PdfViewport(
                key: key,
                image: Future.value(pixel),
                pageIdentity: 'document/page-0',
                pageWidth: 612,
                pageHeight: 1400,
                renderTile: (tile) async {
                  calls.add(tile);
                  return pixel;
                },
              ),
            ),
          ),
        ),
      );
      await settleDetail(tester);
      final first = calls.last;
      expect(first.pageWidth, greaterThanOrEqualTo(912));
      final scale = key.currentState!.transform.value.getMaxScaleOnAxis() * 4;
      final zoomed = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(2, 2, scale)
        ..setTranslationRaw(-400, -500, 0);
      key.currentState!.transform.value = zoomed;
      await tester.pump();
      await settleDetail(tester);
      expect(calls.last.pageWidth, greaterThan(first.pageWidth * 3));
      expect(
        calls.last.pageWidth * calls.last.pageWidth * 1400 / 612,
        greaterThan(maxPdfRasterPixels),
      );
      expect(key.currentState!.transform.value, zoomed);
      final previous = calls.last;
      key.currentState!.transform.value = zoomed.clone()
        ..setTranslationRaw(-800, -1100, 0);
      await tester.pump();
      await settleDetail(tester);
      expect(calls.last.x > previous.x || calls.last.y > previous.y, isTrue);
      for (final tile in calls) {
        expect(tile.width * tile.height, lessThanOrEqualTo(maxPdfRasterPixels));
        expect(tile.width, lessThanOrEqualTo(maxPdfRasterSide));
        expect(tile.height, lessThanOrEqualTo(maxPdfRasterSide));
      }
      expect(find.byKey(const Key('pdf-page-detail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid pan and zoom keep one render running and use only the latest demand',
    (tester) async {
      final preview = Future.value(pixel);
      final calls = <PdfPageTile>[];
      final pending = <Completer<Uint8List>>[];
      Future<Uint8List> render(PdfPageTile tile) {
        calls.add(tile);
        final result = Completer<Uint8List>();
        pending.add(result);
        return result.future;
      }

      await tester.pumpWidget(detailPage(preview, render));
      await settleDetail(tester);
      expect(calls, hasLength(1));
      for (final x in [80.0, 110.0, 140.0]) {
        await tester.pumpWidget(
          detailPage(
            preview,
            render,
            viewport: Rect.fromLTWH(x, 150, 100, 150),
            density: 12,
          ),
        );
        await settleDetail(tester);
        expect(calls, hasLength(1));
      }
      pending.first.complete(pixel);
      await tester.pump();
      expect(find.byKey(const Key('pdf-page-detail')), findsNothing);
      await settleDetail(tester);
      expect(calls, hasLength(2));
      expect(calls.last.x, greaterThan(1000));
      expect(calls.last.y, greaterThan(1000));
      pending.last.complete(pixel);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdf-page-detail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a replaced document cannot display an old detail response', (
    tester,
  ) async {
    final preview = Future.value(pixel);
    final pending = <Completer<Uint8List>>[];
    Future<Uint8List> render(PdfPageTile tile) {
      final result = Completer<Uint8List>();
      pending.add(result);
      return result.future;
    }

    await tester.pumpWidget(detailPage(preview, render, identity: 'first'));
    await settleDetail(tester);
    await tester.pumpWidget(detailPage(preview, render, identity: 'second'));
    await settleDetail(tester);
    expect(pending, hasLength(2));
    pending.first.complete(pixel);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-page-detail')), findsNothing);
    pending.last.complete(pixel);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-page-detail')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed detail keeps the preview without a retry loop', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      detailPage(Future.value(pixel), (tile) async {
        calls++;
        throw const FormatException('Unsupported detail');
      }),
    );
    await settleDetail(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('pdf-page-detail')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large physical viewports stay within the existing pixel budget',
    (tester) async {
      final calls = <PdfPageTile>[];
      await tester.pumpWidget(
        detailPage(Future.value(pixel), (tile) async {
          calls.add(tile);
          return pixel;
        }, density: 16),
      );
      await settleDetail(tester);
      expect(calls, isNotEmpty);
      expect(
        calls.single.width * calls.single.height,
        lessThanOrEqualTo(maxPdfRasterPixels),
      );
      expect(calls.single.width, lessThanOrEqualTo(maxPdfRasterSide));
      expect(calls.single.height, lessThanOrEqualTo(maxPdfRasterSide));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('continuous pages refine visible pages at the current zoom', (
    tester,
  ) async {
    final key = GlobalKey<ContinuousPagesState>();
    final calls = <({int page, PdfPageTile tile})>[];
    final preview = Future.value(pixel);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 400,
            child: ContinuousPages(
              key: key,
              sizes: List.filled(20, const Size(600, 800)),
              page: 0,
              onPageChanged: (_) {},
              pageBuilder: (_, page, view) => PdfPageImage(
                image: preview,
                pageIdentity: page,
                pageSize: const Size(600, 800),
                fit: BoxFit.contain,
                view: view,
                renderTile: (tile) async {
                  calls.add((page: page, tile: tile));
                  return pixel;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await settleDetail(tester);
    final before = calls.first.tile.pageWidth;
    key.currentState!.transform.value = Matrix4.identity()
      ..setEntry(0, 0, 4)
      ..setEntry(1, 1, 4)
      ..setEntry(2, 2, 4)
      ..setTranslationRaw(-300, -400, 0);
    await tester.pump();
    await settleDetail(tester);
    expect(calls.last.tile.pageWidth, greaterThan(before * 2));
    expect(calls.every((call) => call.page <= 1), isTrue);
    expect(tester.takeException(), isNull);
  });
}
