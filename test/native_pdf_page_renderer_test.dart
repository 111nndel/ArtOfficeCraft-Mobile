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

class Fallback implements PdfPageRenderer {
  int opened = 0, rendered = 0;
  final closed = <int>[];
  Completer<int>? opening;
  @override
  bool get supportsOcr => true;
  @override
  Future<int> open(Uint8List bytes) async {
    opened++;
    final pending = opening;
    if (pending != null) return pending.future;
    return opened;
  }

  @override
  Future<Uint8List> render(int session, int page, {int width = 1000}) async {
    rendered++;
    return image();
  }

  @override
  Future<PdfOcrResult> recognize(int session, int page) async =>
      throw StateError('PDF OCR must not be used');
  @override
  Future<void> close(int session) async {
    closed.add(session);
  }
}

void main() {
  test('Rust renders stay on one owned worker; replacement and reopen release sessions', () async {
    final fallback = Fallback();
    final renderer = NativePdfPageRenderer(
      fallback: fallback,
      workerEntry: worker,
    );
    final first = await renderer.open(pdf), second = await renderer.open(pdf);
    await renderer.render(first, 0);
    await renderer.close(first);
    await renderer.render(second, 0);
    await renderer.close(second);
    await renderer.close(second);
    expect(renderer.nativeRenders, 2);
    expect(fallback.opened, 0);
    await expectLater(renderer.render(first, 0), throwsStateError);
    final reopened = await renderer.open(pdf);
    await renderer.render(reopened, 0);
    await renderer.close(reopened);
    expect(renderer.nativeRenders, 3);
  });

  test(
    'unsupported page opens fallback once; OCR receives a Rust image',
    () async {
      final fallback = Fallback();
      var images = 0;
      final renderer = NativePdfPageRenderer(
        fallback: fallback,
        workerEntry: worker,
        recognizeImage: (png) async {
          expect(png, image());
          images++;
          return (text: 'image OCR', words: <PdfOcrWord>[]);
        },
      );
      final session = await renderer.open(pdf);
      await Future.wait([
        renderer.render(session, 3),
        renderer.render(session, 3),
      ]);
      expect((await renderer.recognize(session, 0)).text, 'image OCR');
      expect(images, 1);
      expect(renderer.nativeRenders, 1);
      expect(renderer.supportsOcr, isTrue);
      expect(fallback.opened, 1);
      expect(fallback.rendered, 2);
      expect(renderer.fallbackRenders, 2);
      await renderer.close(session);
      expect(fallback.closed, [1]);
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

  test(
    'close waits for late fallback open and never publishes its stale page',
    () async {
      final fallback = Fallback()..opening = Completer<int>();
      final renderer = NativePdfPageRenderer(
        fallback: fallback,
        workerEntry: worker,
      );
      final session = await renderer.open(pdf);
      final rendering = expectLater(
        renderer.render(session, 3),
        throwsStateError,
      );
      while (fallback.opened == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final closing = renderer.close(session);
      fallback.opening!.complete(71);
      await closing;
      await rendering;
      expect(fallback.closed, [71]);
      expect(fallback.rendered, 0);
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
    expect(renderer.fallbackRenders, 0);
    await renderer.close(session);
    await expectLater(renderer.recognize(session, 0), throwsStateError);
    final unavailable = NativePdfPageRenderer(
      fallback: Fallback(),
      workerEntry: worker,
    );
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
