import 'dart:async';
import 'dart:isolate';

/// A single owned worker. Requests are processed in order; failures are never replayed.
typedef DocumentWorkerEntry = void Function((SendPort, Map<String, Object?>));

class DocumentWorker {
  DocumentWorker(this.entry, {this.configuration = const {}});
  final DocumentWorkerEntry entry;
  final Map<String, Object?> configuration;
  ReceivePort? _replies, _errors, _exit;
  Completer<SendPort>? _ready;
  SendPort? _port;
  final _exited = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  int _next = 0;
  int starts = 0;
  bool _closed = false, _failed = false, _expectedExit = false;
  Future<void>? _closing;

  Future<SendPort> _start() {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<SendPort>();
    _replies = ReceivePort();
    _errors = ReceivePort();
    _exit = ReceivePort();
    _replies!.listen((message) {
      if (message is SendPort) {
        _port = message;
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is! List || message.length < 3 || message[0] is! int) {
        _fail(StateError('Invalid document worker response'));
        return;
      }
      final request = _pending.remove(message[0]);
      if (request == null) return;
      if (message[1] == true) {
        request.complete(message[2]);
      } else {
        final details = message[2] as List;
        final type = details[0] as String, text = details[1] as String;
        final error = type == 'FormatException'
            ? FormatException(text)
            : StateError(text);
        request.completeError(
          error,
          StackTrace.fromString(details[2] as String),
        );
      }
    });
    _errors!.listen(
      (error) => _fail(StateError('Document worker failed: $error')),
    );
    _exit!.listen((_) {
      if (!_exited.isCompleted) _exited.complete();
      if (!_expectedExit) {
        _fail(
          StateError(
            'Document worker stopped. Reopen the document to continue.',
          ),
        );
      }
      if (_failed) _releasePorts();
    });
    starts++;
    Isolate.spawn(
      entry,
      (_replies!.sendPort, configuration),
      onError: _errors!.sendPort,
      onExit: _exit!.sendPort,
      errorsAreFatal: true,
      debugName: 'ArtOfficeCraft document',
    ).then(
      (isolate) {
        // Native work stays alive until the ordered close handshake.
      },
      onError: (Object error, StackTrace stack) {
        _fail(error);
        if (!_exited.isCompleted) _exited.complete();
        _releasePorts();
      },
    );
    return ready.future;
  }

  void _fail(Object error) {
    _failed = true;
    _port?.send([0, 'worker.terminate', null]);
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
  }

  Future<Object?> request(String operation, Object? payload) =>
      _request(operation, payload, internal: false);
  Future<Object?> _request(
    String operation,
    Object? payload, {
    required bool internal,
  }) async {
    if (_failed || _closed && !internal) {
      throw StateError('Document worker is closed');
    }
    final port = await _start();
    if (_failed || _closed && !internal) {
      throw StateError('Document worker is closed');
    }
    final id = ++_next, result = Completer<Object?>();
    _pending[id] = result;
    try {
      port.send([id, operation, payload]);
    } catch (error, stack) {
      _pending.remove(id);
      result.completeError(error, stack);
    }
    return result.future;
  }

  /// Drain replies before terminating, so an in-flight FFI call can release buffers.
  /// No forced isolate kill while Rust owns borrowed input or result allocations.
  Future<void> close() => _closing ??= (() async {
    _closed = true;
    if (_ready == null) return;
    try {
      final port = await _ready!.future;
      await _request('worker.drain', null, internal: true);
      _expectedExit = true;
      port.send([0, 'worker.terminate', null]);
    } catch (_) {
      /* An exited worker already failed its pending requests. */
    }
    await _exited.future;
    _releasePorts();
    _port = null;
  })();

  void _releasePorts() {
    _replies?.close();
    _errors?.close();
    _exit?.close();
    _replies = null;
    _errors = null;
    _exit = null;
  }
}

/// One serial loop, shared by the native engine and isolated transport tests.
Future<void> serveDocumentWorker(
  SendPort reply,
  FutureOr<Object?> Function(String, Object?) execute,
) async {
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  try {
    await for (final raw in inbox) {
      final message = raw as List;
      final id = message[0] as int, operation = message[1] as String;
      if (operation == 'worker.terminate') break;
      try {
        final value = operation == 'worker.drain'
            ? null
            : await execute(operation, message[2]);
        reply.send([id, true, value]);
      } catch (error, stack) {
        reply.send([
          id,
          false,
          [
            error.runtimeType.toString(),
            error is FormatException
                ? error.message
                : error is StateError
                ? error.message.toString()
                : error.toString(),
            stack.toString(),
          ],
        ]);
      }
    }
  } finally {
    inbox.close();
  }
}
