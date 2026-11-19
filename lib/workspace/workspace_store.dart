import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editor_kind.dart';
import '../platform/application_storage.dart';

class WorkspaceFile {
  const WorkspaceFile({
    required this.id,
    required this.name,
    required this.kind,
    required this.modified,
    this.favorite = false,
    this.recent = true,
  });
  final String id, name;
  final EditorKind kind;
  final DateTime modified;
  final bool favorite;
  final bool recent;
  WorkspaceFile copyWith({
    String? name,
    DateTime? modified,
    bool? favorite,
    bool? recent,
  }) => WorkspaceFile(
    id: id,
    name: name ?? this.name,
    kind: kind,
    modified: modified ?? this.modified,
    favorite: favorite ?? this.favorite,
    recent: recent ?? this.recent,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'modified': modified.toIso8601String(),
    'favorite': favorite,
    'recent': recent,
  };
  factory WorkspaceFile.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    if (!RegExp(r'^f[0-9]+$').hasMatch(id)) {
      throw const FormatException('Invalid file id');
    }
    return WorkspaceFile(
      id: id,
      name: json['name'] as String,
      kind: EditorKind.values.byName(json['kind'] as String),
      modified: DateTime.parse(json['modified'] as String),
      favorite: json['favorite'] == true,
      // Existing installations retain their recent list on the first upgrade.
      recent: json['recent'] != false,
    );
  }
}

/// App-private copies of opened/exported documents and applied Grid edits.
/// Unsaved native editing sessions keep their existing explicit Save As guard.
class WorkspaceStore extends ChangeNotifier {
  WorkspaceStore({
    this._directory,
    this.storage = const AndroidApplicationStorage(),
  });
  final ApplicationStorage storage;
  Directory? _directory;
  List<WorkspaceFile> _files = const [];
  List<WorkspaceFile> get files => _files;
  bool loaded = false;
  String? error;
  Future<void> _queue = Future.value();

  Future<Directory> _root() async {
    if (_directory != null) return _directory!;
    return _directory = await storage.workspaceDirectory();
  }

  Future<void> load() => _serialize(() async {
    try {
      final root = await _root();
      final index = File('${root.path}/index.json');
      if (await index.exists()) {
        final raw = jsonDecode(await index.readAsString()) as List;
        // For a large index a single directory listing avoids a stat per copy.
        final existing = raw.length >= 32
            ? await root.list().where((file) => file is File)
                .map((file) => file.uri.pathSegments.last).toSet()
            : null;
        final next = <WorkspaceFile>[];
        for (final item in raw) {
          final entry = WorkspaceFile.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          final name = '${entry.id}.${entry.kind.extension}';
          if (existing?.contains(name) ?? await File('${root.path}/$name').exists()) {
            next.add(entry);
          }
        }
        next.sort(_newestFirst);
        _files = List.unmodifiable(next);
      } else {
        _files = const [];
      }
      error = null;
    } on MissingPluginException {
      error = 'История файлов доступна в Android-приложении.';
    } catch (_) {
      // Keep a failed index intact rather than silently overwriting it later.
      error = 'Не удалось прочитать историю. Исходные файлы не изменены.';
    }
    loaded = true;
    notifyListeners();
  });

  static int _newestFirst(WorkspaceFile a, WorkspaceFile b) =>
      b.modified.compareTo(a.modified);

  void _requireWritable() {
    if (!loaded || error != null) {
      throw StateError(error ?? 'История ещё загружается');
    }
  }

  Future<void> _writeIndex(Directory root, List<WorkspaceFile> values) async {
    final target = File('${root.path}/index.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(values.map((f) => f.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(target.path);
  }

  Future<T> _serialize<T>(Future<T> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<WorkspaceFile> remember(
    EditorKind kind,
    Uint8List bytes,
    String name, {
    String? id,
  }) => _serialize(() async {
    _requireWritable();
    final root = await _root();
    if (bytes.isEmpty || bytes.length > 128 * 1024 * 1024) {
      throw const FormatException('Размер файла вне допустимых границ');
    }
    final oldIndex = id == null
        ? -1
        : _files.indexWhere((f) => f.id == id && f.kind == kind);
    final old = oldIndex < 0 ? null : _files[oldIndex];
    final entry = WorkspaceFile(
      id: old?.id ?? 'f${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      kind: kind,
      modified: DateTime.now(),
      favorite: old?.favorite ?? false,
    );
    final file = File('${root.path}/${entry.id}.${kind.extension}');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    final next = [..._files.where((f) => f.id != entry.id), entry]
      ..sort(_newestFirst);
    await _writeIndex(root, next);
    _files = List.unmodifiable(next);
    notifyListeners();
    return entry;
  });
  Future<void> toggleFavorite(WorkspaceFile file) => _serialize(() async {
    _requireWritable();
    final index = _files.indexWhere((entry) => entry.id == file.id);
    if (index == -1) return;
    final current = _files[index];
    final next = [..._files]
      ..[index] = current.copyWith(favorite: !current.favorite);
    await _writeIndex(await _root(), next);
    _files = List.unmodifiable(next);
    notifyListeners();
  });

  /// Hide or restore history entries without changing documents or favorites.
  /// Snapshot IDs before queueing so later selection changes cannot affect work.
  Future<Set<String>> setRecent(Iterable<String> ids, bool value) {
    final targets = Set<String>.of(ids);
    return _serialize(() async {
      _requireWritable();
      final changed = _files
          .where((f) => targets.contains(f.id) && f.recent != value)
          .map((f) => f.id)
          .toSet();
      if (changed.isEmpty) return <String>{};
      final next = _files
          .map((f) => changed.contains(f.id) ? f.copyWith(recent: value) : f)
          .toList();
      await _writeIndex(await _root(), next);
      _files = List.unmodifiable(next);
      notifyListeners();
      return Set<String>.unmodifiable(changed);
    });
  }

  Future<Uint8List> read(WorkspaceFile entry) async {
    final file = File(
      '${(await _root()).path}/${entry.id}.${entry.kind.extension}',
    );
    if (await file.length() > 128 * 1024 * 1024) {
      throw const FormatException('Файл слишком большой');
    }
    return file.readAsBytes();
  }
}

/// A file opened from inside an editor must not overwrite the previous import.
class WorkspaceDocumentSession {
  WorkspaceDocumentSession(this.store, this.kind, {this.id});
  final WorkspaceStore store;
  final EditorKind kind;
  String? id;
  void startDocument() => id = null;
  Future<void> remember(Uint8List bytes, String name) async {
    id = (await store.remember(kind, bytes, name, id: id)).id;
  }
}
