import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_worker.dart';
import 'package:artofficecraft_mobile/native/native_pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List image() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
final pdf = Uint8List.fromList(ascii.encode('%PDF-test'));

void worker((SendPort, Map<String, Object?>) args) {
  var next = 0;
  final sessions = <int>{};
  serveDocumentWorker(args.$1, (operation, payload) async {
    final request = payload as Map;
    switch (request['op']) {
      case 'open':
        if (ascii.decode(request['bytes'] as Uint8List).contains('reject')) {
          throw const FormatException('Unsupported PDF document');
        }
        sessions.add(++next);
        return Uint8List.fromList(
          utf8.encode(jsonEncode({'session': next, 'pageCount': 4})),
        );
      case 'close':
        if (!sessions.remove(request['session'])) {
          throw StateError('Double close');
        }
        return Uint8List(0);
      case 'page':
      case 'tile':
        if (!sessions.contains(request['session'])) {
          throw StateError('Closed native session');
        }
        if (request['page'] == 3) {
          throw const FormatException('Unsupported PDF feature');
        }
        if (request['page'] == 2) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        return image();
      default:
        throw StateError('Unexpected operation');
    }
  });
}

void main() {
  test(
    'invalid and unsupported documents fail and a new session can still open',
    () async {
      final renderer = NativePdfPageRenderer(workerEntry: worker);
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList(ascii.encode('wrong header')),
        Uint8List.fromList(ascii.encode('%PDF-reject')),
      ]) {
        await expectLater(renderer.open(bytes), throwsFormatException);
      }
      final session = await renderer.open(pdf);
      expect(await renderer.render(session, 0), image());
      await renderer.close(session);
      expect(renderer.nativeRenders, 1);
    },
  );

  test(
    'detail renders reuse the native session and keep tile allocations bounded',
    () async {
      final renderer = NativePdfPageRenderer(workerEntry: worker);
      final session = await renderer.open(pdf);
      const tile = (pageWidth: 6000, x: 2048, y: 3000, width: 1, height: 1);
      expect(await renderer.renderTile(session, 0, tile), image());
      expect(renderer.nativeRenders, 1);
      await expectLater(
        renderer.renderTile(session, 0, (
          pageWidth: 6000,
          x: 0,
          y: 0,
          width: 2880,
          height: 2880,
        )),
        throwsRangeError,
      );
      await expectLater(
        renderer.renderTile(session, 0, (
          pageWidth: 6000,
          x: 5999,
          y: 0,
          width: 2,
          height: 1,
        )),
        throwsRangeError,
      );
      await renderer.close(session);
      await expectLater(
        renderer.renderTile(session, 0, tile),
        throwsStateError,
      );
    },
  );
  test('detail results with different dimensions are rejected', () async {
    final renderer = NativePdfPageRenderer(workerEntry: worker);
    final session = await renderer.open(pdf);
    await expectLater(
      renderer.renderTile(session, 0, (
        pageWidth: 6000,
        x: 0,
        y: 0,
        width: 64,
        height: 64,
      )),
      throwsFormatException,
    );
    await renderer.close(session);
  });
  test(
    'closing a document during detail rendering rejects the late image',
    () async {
      final renderer = NativePdfPageRenderer(workerEntry: worker);
      final session = await renderer.open(pdf);
      final pending = renderer.renderTile(session, 2, (
        pageWidth: 6000,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ));
      final rejected = expectLater(pending, throwsStateError);
      await renderer.close(session);
      await rejected;
    },
  );
  test('Rust renders stay on one owned worker; replacement and reopen release sessions', () async {
    final renderer = NativePdfPageRenderer(workerEntry: worker);
    final first = await renderer.open(pdf), second = await renderer.open(pdf);
    await renderer.render(first, 0);
    await renderer.close(first);
    await renderer.render(second, 0);
    await renderer.close(second);
    await renderer.close(second);
    expect(renderer.nativeRenders, 2);
    await expectLater(renderer.render(first, 0), throwsStateError);
    final reopened = await renderer.open(pdf);
    await renderer.render(reopened, 0);
    await renderer.close(reopened);
    expect(renderer.nativeRenders, 3);
  });

  test(
    'unsupported pages report errors; image OCR still receives Rust rasters',
    () async {
      var images = 0;
      final renderer = NativePdfPageRenderer(
        workerEntry: worker,
        recognizeImage: (png) async {
          expect(png, image());
          images++;
          return (text: 'image OCR', words: <PdfOcrWord>[]);
        },
      );
      final session = await renderer.open(pdf);
      await Future.wait([
        expectLater(renderer.render(session, 3), throwsFormatException),
        expectLater(renderer.render(session, 3), throwsFormatException),
      ]);
      expect((await renderer.recognize(session, 0)).text, 'image OCR');
      expect(images, 1);
      expect(renderer.nativeRenders, 1);
      expect(renderer.supportsOcr, isTrue);
      await renderer.close(session);
    },
  );

  test(
    'close during native rendering discards stale result and drains worker',
    () async {
      final renderer = NativePdfPageRenderer(workerEntry: worker);
      expect(renderer.supportsOcr, isFalse);
      final session = await renderer.open(pdf);
      final rendering = expectLater(
        renderer.render(session, 2),
        throwsStateError,
      );
      await renderer.close(session);
      await rendering;
      expect(renderer.nativeRenders, 0);
    },
  );

  test('image OCR works with Rust alone and rejects unavailable OCR', () async {
    final renderer = NativePdfPageRenderer(
      workerEntry: worker,
      recognizeImage: (png) async =>
          (text: 'portable image', words: <PdfOcrWord>[]),
    );
    final session = await renderer.open(pdf);
    expect(renderer.supportsOcr, isTrue);
    expect((await renderer.recognize(session, 0)).text, 'portable image');
    expect(renderer.nativeRenders, 1);
    await renderer.close(session);
    await expectLater(renderer.recognize(session, 0), throwsStateError);
    final unavailable = NativePdfPageRenderer(workerEntry: worker);
    final other = await unavailable.open(pdf);
    expect(unavailable.supportsOcr, isFalse);
    await expectLater(unavailable.recognize(other, 0), throwsUnsupportedError);
    await expectLater(unavailable.recognize(other, -1), throwsRangeError);
    await unavailable.close(other);
  });

  test(
    'close during rasterization never starts OCR; late OCR is discarded',
    () async {
      final pending = Completer<PdfOcrResult>();
      final started = Completer<void>();
      final renderer = NativePdfPageRenderer(
        workerEntry: worker,
        recognizeImage: (png) {
          started.complete();
          return pending.future;
        },
      );
      final first = await renderer.open(pdf);
      final rasterizing = expectLater(
        renderer.recognize(first, 2),
        throwsStateError,
      );
      await renderer.close(first);
      await rasterizing;
      expect(started.isCompleted, isFalse);
      final second = await renderer.open(pdf);
      final recognizing = expectLater(
        renderer.recognize(second, 0),
        throwsStateError,
      );
      await started.future;
      await renderer.close(second);
      pending.complete((text: 'closed document', words: <PdfOcrWord>[]));
      await recognizing;
    },
  );
}
