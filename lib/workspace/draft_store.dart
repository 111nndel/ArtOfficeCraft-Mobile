import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'editor_kind.dart';

Future<List<int>> _encodeDraft(Map<String, dynamic> data) =>
    Isolate.run(() => utf8.encode(jsonEncode(data)));

String _nonce(int count) {
  final random = Random.secure();
  return List.generate(
    count,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class DraftInfo {
  const DraftInfo({
    required this.id,
    required this.kind,
    required this.name,
    required this.base,
    required this.modified,
    this.workspaceId,
  });
  final String id, name, base;
  final EditorKind kind;
  final DateTime modified;
  final String? workspaceId;
  static final idPattern = RegExp(r'^r[0-9a-f]{32}$');
  factory DraftInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final base = json['base'] as String;
    if (json['schema'] != 1 ||
        !idPattern.hasMatch(id) ||
        !RegExp('^$id-b[0-9a-f]{16}\\.bin\$').hasMatch(base)) {
      throw const FormatException('Invalid recovery record');
    }
    return DraftInfo(
      id: id,
      kind: EditorKind.values.byName(json['kind'] as String),
      name: json['name'] as String,
      base: base,
      modified: DateTime.parse(json['modified'] as String),
      workspaceId: json['workspaceId'] as String?,
    );
  }
}

class RecoveredDraft {
  const RecoveredDraft(this.info, this.bytes, this.editor);
  final DraftInfo info;
  final Uint8List bytes;
  final Map<String, dynamic> editor;
}

/// Immutable Office snapshots + an atomically replaced, small editor journal.
/// The manifest never references an incomplete snapshot; typing reuses its base.
class DraftStore extends ChangeNotifier {
  DraftStore({this.directory});
  final Directory? directory;
  Future<Directory>? _rootFuture;
  Future<void> _queue = Future.value();
  final List<DraftInfo> _items = [];
  List<DraftInfo> get items => List.unmodifiable(_items);
  bool loaded = false, _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String? error;
  static const channel = MethodChannel('artofficecraft/workspace');
  static const maxDocumentBytes = 64 * 1024 * 1024,
      maxJournalBytes = 4 * 1024 * 1024;
  Future<Directory> _root() => _rootFuture ??= (() async {
    final base = directory;
    if (base != null) return base.create(recursive: true);
    final path = await channel.invokeMethod<String>('directory');
    if (path == null) {
      throw const FileSystemException('Recovery storage unavailable');
    }
    return Directory('$path/drafts').create(recursive: true);
  })();
  Future<T> _serialize<T>(Future<T> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _publish(DraftInfo? info, String id) {
    _items.removeWhere((x) => x.id == id);
    if (info != null) _items.add(info);
    _items.sort((a, b) => b.modified.compareTo(a.modified));
    _notify();
  }

  Future<Map<String, dynamic>> _manifest(File file) async {
    if (await file.length() > maxJournalBytes) {
      throw const FormatException('Recovery journal too large');
    }
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> load() => _serialize(() async {
    final next = <DraftInfo>[];
    var damaged = false;
    try {
      final root = await _root();
      await for (final entry in root.list()) {
        if (entry is! File ||
            !RegExp(r'r[0-9a-f]{32}\.json$').hasMatch(entry.path)) {
          continue;
        }
        try {
          final info = DraftInfo.fromJson(await _manifest(entry));
          if (!entry.path.endsWith('/${info.id}.json') &&
              !entry.path.endsWith('\\${info.id}.json')) {
            throw const FormatException('Recovery id mismatch');
          }
          final base = File('${root.path}/${info.base}');
          final length = await base.length();
          if (length == 0 || length > maxDocumentBytes) {
            throw const FormatException('Invalid recovery document');
          }
          next.add(info);
        } catch (_) {
          damaged = true;
        }
      }
      _items
        ..clear()
        ..addAll(next);
      _items.sort((a, b) => b.modified.compareTo(a.modified));
      error = damaged
          ? 'Часть черновиков не удалось прочитать. Их файлы сохранены.'
          : null;
    } on MissingPluginException {
      error = null;
    } catch (_) {
      error = 'Не удалось открыть локальные черновики.';
    }
    loaded = true;
    _notify();
  });
  Future<RecoveredDraft> read(String id) => _serialize(() async {
    if (!DraftInfo.idPattern.hasMatch(id)) {
      throw const FormatException('Invalid recovery id');
    }
    final root = await _root();
    final json = await _manifest(File('${root.path}/$id.json'));
    final info = DraftInfo.fromJson(json);
    if (info.id != id) {
      throw const FormatException('Recovery identity mismatch');
    }
    final file = File('${root.path}/${info.base}');
    final length = await file.length();
    if (length == 0 || length > maxDocumentBytes) {
      throw const FormatException('Invalid recovery document');
    }
    return RecoveredDraft(
      info,
      await file.readAsBytes(),
      Map<String, dynamic>.from(json['editor'] as Map),
    );
  });
  Future<DraftInfo> write({
    required String id,
    required EditorKind kind,
    required String name,
    required Uint8List bytes,
    required Map<String, dynamic> editor,
    String? workspaceId,
    String? reuseBase,
  }) => _serialize(() async {
    if (!DraftInfo.idPattern.hasMatch(id) ||
        bytes.isEmpty ||
        bytes.length > maxDocumentBytes) {
      throw const FormatException('Invalid recovery snapshot');
    }
    final root = await _root();
    final target = File('${root.path}/$id.json');
    if (await target.exists()) {
      // Preserve an unreadable record instead of overwriting a possibly useful draft.
      final old = DraftInfo.fromJson(await _manifest(target));
      if (old.id != id) {
        throw const FormatException('Recovery identity mismatch');
      }
    }
    final reusable =
        reuseBase != null &&
        RegExp('^$id-b[0-9a-f]{16}\\.bin\$').hasMatch(reuseBase) &&
        await File('${root.path}/$reuseBase').exists() &&
        await File('${root.path}/$reuseBase').length() == bytes.length;
    final base = reusable ? reuseBase : '$id-b${_nonce(8)}.bin';
    final modified = DateTime.now();
    final data = await _encodeDraft({
      'schema': 1,
      'id': id,
      'kind': kind.name,
      'name': name,
      'base': base,
      'modified': modified.toIso8601String(),
      'workspaceId': workspaceId,
      'editor': editor,
    });
    if (data.length > maxJournalBytes) {
      throw const FormatException('Recovery input too large');
    }
    if (!reusable) {
      final tmp = File('${root.path}/$base.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename('${root.path}/$base');
    }
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(target.path);
    final info = DraftInfo(
      id: id,
      kind: kind,
      name: name,
      base: base,
      modified: modified,
      workspaceId: workspaceId,
    );
    _publish(info, id);
    await for (final entry in root.list()) {
      if (entry is File &&
          !entry.path.endsWith('/$base') &&
          !entry.path.endsWith('\\$base') &&
          RegExp('$id-b[0-9a-f]{16}\\.bin(?:\\.tmp)?\$').hasMatch(entry.path)) {
        try {
          await entry.delete();
        } catch (_) {
          /* A valid manifest already owns the new base. */
        }
      }
    }
    return info;
  });
  Future<void> remove(String id) => _serialize(() async {
    if (!DraftInfo.idPattern.hasMatch(id)) {
      throw const FormatException('Invalid recovery id');
    }
    final root = await _root();
    final file = File('${root.path}/$id.json');
    if (await file.exists()) await file.delete();
    _publish(null, id);
    await for (final entry in root.list()) {
      if (entry is File &&
          (entry.path.endsWith('/$id.json.tmp') ||
              entry.path.endsWith('\\$id.json.tmp') ||
              RegExp('$id-b[0-9a-f]{16}\\.bin(?:\\.tmp)?\$')
                  .hasMatch(entry.path))) {
        try {
          await entry.delete();
        } catch (_) {
          /* Manifest is already retired. */
        }
      }
    }
  });
}

class _Checkpoint {
  const _Checkpoint(this.bytes, this.name, this.editor, this.revision);
  final Uint8List bytes;
  final String name;
  final Map<String, dynamic> editor;
  final int revision;
}

/// Debounced raw input, serialized writes, and a pause/close flush. No Rust per key.
class DraftSession extends ChangeNotifier with WidgetsBindingObserver {
  DraftSession(
    this.store,
    this.kind, {
    String? id,
    this.workspaceId,
    this.onError,
    this.delay = const Duration(milliseconds: 350),
  }) : id = id ?? 'r${_nonce(16)}',
       _hasCheckpoint = id != null {
    WidgetsBinding.instance.addObserver(this);
  }
  final DraftStore store;
  final EditorKind kind;
  final String id;
  String? workspaceId;
  final VoidCallback? onError;
  final Duration delay;
  Timer? _timer;
  Future<void> _queue = Future.value();
  Future<void>? _closing;
  _Checkpoint? _latest;
  Uint8List? _baseBytes;
  String? _base;
  int _epoch = 0, _revision = 0;
  bool _hasCheckpoint, _discarded = false, _closed = false, _reported = false;
  void _report() {
    if (!_reported) {
      _reported = true;
      onError?.call();
    }
  }

  String status = '';
  void _status(String value) {
    if (status != value && !_closed) {
      status = value;
      notifyListeners();
    }
  }

  Future<void> _serialize(Future<void> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void update({
    required Uint8List bytes,
    required String name,
    required Map<String, dynamic> editor,
    required bool dirty,
  }) {
    if (_discarded || _closed) return;
    if (!dirty) {
      unawaited(clear());
      return;
    }
    _latest = _Checkpoint(bytes, name, editor, ++_revision);
    _timer?.cancel();
    _status(' · Черновик…');
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final checkpoint = _latest;
    _latest = null;
    if (checkpoint == null || _discarded) return _queue;
    final epoch = _epoch;
    return _serialize(() async {
      if (epoch != _epoch || _discarded) return;
      try {
        final info = await store.write(
          id: id,
          kind: kind,
          name: checkpoint.name,
          bytes: checkpoint.bytes,
          editor: checkpoint.editor,
          workspaceId: workspaceId,
          reuseBase: identical(_baseBytes, checkpoint.bytes) ? _base : null,
        );
        _baseBytes = checkpoint.bytes;
        _base = info.base;
        _hasCheckpoint = true;
        _reported = false;
        if (epoch == _epoch &&
            checkpoint.revision == _revision &&
            _latest == null) {
          _status(' · Черновик сохранён');
        }
      } catch (_) {
        if (epoch == _epoch && checkpoint.revision == _revision) {
          _latest ??= checkpoint;
          _status(' · Черновик не записан');
          _report();
        }
      }
    });
  }

  Future<void> clear() {
    _timer?.cancel();
    _timer = null;
    _latest = null;
    _epoch++;
    if (!_hasCheckpoint && _base == null && status.isEmpty) return _queue;
    _status('');
    return _serialize(() async {
      try {
        await store.remove(id);
        _hasCheckpoint = false;
        _baseBytes = null;
        _base = null;
      } catch (_) {
        _status(' · Черновик не удалён');
        _report();
      }
    });
  }

  Future<void> discard() async {
    _timer?.cancel();
    _timer = null;
    _latest = null;
    _epoch++;
    _discarded = true;
    try {
      await _serialize(() => store.remove(id));
      _hasCheckpoint = false;
      _baseBytes = null;
      _base = null;
      _status('');
    } catch (_) {
      _discarded = false;
      _status(' · Черновик не удалён');
      _report();
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(flush());
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    dispose();
    return _closing!;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _closing = (() async {
      await flush();
      await _queue;
    })();
    super.dispose();
  }
}
