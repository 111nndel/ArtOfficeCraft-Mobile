import 'dart:isolate';

import 'package:artofficecraft_mobile/native/document_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void fakeWorker((SendPort, Map<String, Object?>) config) {
  var count = 0;
  serveDocumentWorker(config.$1, (operation, payload) async {
    if (operation == 'exit') Isolate.exit();
    if (operation == 'invalid') throw const FormatException('bad document');
    if (operation == 'slow') {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return [++count, payload];
  });
}

void startupFailure((SendPort, Map<String, Object?>) config) {
  throw StateError('failed startup');
}

void main() {
  test('One worker processes concurrent requests in order and survives a document error', () async {
    final worker = DocumentWorker(fakeWorker);
    addTearDown(worker.close);
    final result = await Future.wait([
      worker.request('slow', 'first'),
      worker.request('echo', 'second'),
    ]);
    expect(result, [
      [1, 'first'],
      [2, 'second'],
    ]);
    expect(worker.starts, 1);
    await expectLater(worker.request('invalid', null), throwsFormatException);
    expect(await worker.request('echo', 'next'), [3, 'next']);
  });
  test(
    'Close drains accepted work, then rejects new work; repeated close is safe',
    () async {
      final worker = DocumentWorker(fakeWorker);
      await worker.request('echo', 'ready');
      final slow = worker.request('slow', 'completed');
      // Let the request reach the port before close begins.
      await Future<void>.delayed(Duration.zero);
      final closing = worker.close();
      expect(await slow, [2, 'completed']);
      await closing.timeout(const Duration(seconds: 3));
      await worker.close();
      await expectLater(worker.request('echo', 'late'), throwsStateError);
    },
  );
  test('Closing during startup settles every waiting request without an orphan worker', () async {
    final worker = DocumentWorker(fakeWorker);
    final future = worker.request('slow', 'queued');
    final failure = expectLater(future, throwsStateError);
    await worker.close().timeout(const Duration(seconds: 3));
    await failure;
    expect(worker.starts, 1);
  });
  test(
    'Unexpected exit fails pending work instead of hanging or replaying it',
    () async {
      final worker = DocumentWorker(fakeWorker);
      await expectLater(
        worker.request('exit', null).timeout(const Duration(seconds: 3)),
        throwsStateError,
      );
      await expectLater(worker.request('echo', 'retry'), throwsStateError);
      expect(worker.starts, 1);
      await worker.close().timeout(const Duration(seconds: 3));
    },
  );
  test('Startup failure settles both request and close', () async {
    final worker = DocumentWorker(startupFailure);
    await expectLater(
      worker.request('echo', null).timeout(const Duration(seconds: 3)),
      throwsStateError,
    );
    await worker.close().timeout(const Duration(seconds: 3));
  });
}
