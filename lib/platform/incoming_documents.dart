import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../workspace/editor_kind.dart';

class IncomingDocument {
  const IncomingDocument(this.kind, this.name, this.bytes);
  final EditorKind kind;
  final String name;
  final Uint8List bytes;
}

abstract interface class IncomingDocuments {
  void start(
    Future<void> Function(IncomingDocument) receive,
    void Function(Object) error,
  );
  void dispose();
}

/// Android supplies a bounded, app-private temporary copy, never a raw URI path.
/// All routing and names are shared Dart logic; native engines validate content.
class AndroidIncomingDocuments implements IncomingDocuments {
  AndroidIncomingDocuments({MethodChannel? channel})
    : channel =
          channel ?? const MethodChannel('artofficecraft/incoming_documents');
  final MethodChannel channel;
  bool _closed = false, _reading = false, _requested = false;
  late Future<void> Function(IncomingDocument) _receive;
  late void Function(Object) _error;

  static (EditorKind, String) identify(String name, String? mime) {
    name = name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    if (name.length > 255) name = name.substring(0, 255);
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    final byName = EditorKind.values
        .where((k) => k.extension == extension)
        .firstOrNull;
    final type = mime?.split(';').first.trim().toLowerCase();
    final byType = EditorKind.values
        .where((k) => k.mimeType == type)
        .firstOrNull;
    if (byName != null && byType != null && byName != byType) {
      throw const FormatException('Conflicting document type');
    }
    final kind = byName ?? byType;
    if (kind == null) throw const FormatException('Unsupported document type');
    if (name.isEmpty) name = 'Document';
    if (byName == null) name = '$name.${kind.extension}';
    return (kind, name);
  }

  @override
  void start(
    Future<void> Function(IncomingDocument) receive,
    void Function(Object) error,
  ) {
    _receive = receive;
    _error = error;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'available') _request();
      if (call.method == 'error' && !_closed) {
        _error(StateError('Incoming file queue is full'));
      }
    });
    _request();
  }

  void _request() {
    if (_closed) return;
    _requested = true;
    if (!_reading) unawaited(_drain());
  }

  Future<void> _drain() async {
    _reading = true;
    try {
      while (_requested && !_closed) {
        _requested = false;
        while (!_closed) {
          Map? item;
          try {
            item = await channel.invokeMapMethod('take');
            if (item == null) break;
            final path = item['path'] as String;
            try {
              final (kind, name) = identify(
                item['name'] as String? ?? '',
                item['mime'] as String?,
              );
              final file = File(path);
              final length = await file.length();
              if (length == 0 || length > 64 * 1024 * 1024) {
                throw const FormatException('Document size is outside limits');
              }
              final bytes = await file.readAsBytes();
              if (bytes.isEmpty || bytes.length > 64 * 1024 * 1024) {
                throw const FormatException('Document size is outside limits');
              }
              if (!_closed) await _receive(IncomingDocument(kind, name, bytes));
            } finally {
              await channel.invokeMethod<void>('release', {'path': path});
            }
          } on MissingPluginException {
            return;
          } catch (error) {
            if (!_closed) _error(error);
          }
        }
      }
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    channel.setMethodCallHandler(null);
  }
}
