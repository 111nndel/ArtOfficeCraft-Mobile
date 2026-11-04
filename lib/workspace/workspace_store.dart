import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editor_kind.dart';

class WorkspaceFile {
  const WorkspaceFile({
    required this.id,
    required this.name,
    required this.kind,
    required this.modified,
    this.favorite = false,
  });
  final String id, name;
  final EditorKind kind;
  final DateTime modified;
  final bool favorite;
  WorkspaceFile copyWith({String? name, DateTime? modified, bool? favorite}) =>
      WorkspaceFile(
        id: id,
        name: name ?? this.name,
        kind: kind,
        modified: modified ?? this.modified,
        favorite: favorite ?? this.favorite,
      );
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'modified': modified.toIso8601String(),
    'favorite': favorite,
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
    );
  }
}

/// App-private copies of opened/exported documents and applied Grid edits.
/// Unsaved native editing sessions keep their existing explicit Save As guard.
class WorkspaceStore extends ChangeNotifier {
  WorkspaceStore({this._directory});
  Directory? _directory;
  final List<WorkspaceFile> _files = [];
  List<WorkspaceFile> get files => List.unmodifiable(_files);
  bool loaded = false;
  String? error;
  Future<void> _queue = Future.value();
  static const _channel = MethodChannel('artofficecraft/workspace');

  Future<Directory> _root() async {
    if (_directory != null) return _directory!;
    final path = await _channel.invokeMethod<String>('directory');
    if (path == null) throw const FileSystemException('Хранилище недоступно');
    return _directory = await Directory(path).create(recursive: true);
  }

  Future<void> load() async {
    try {
      final root = await _root();
      final index = File('${root.path}/index.json');
      if (await index.exists()) {
        final raw = jsonDecode(await index.readAsString()) as List;
        final next = <WorkspaceFile>[];
        for (final item in raw) {
          final entry = WorkspaceFile.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          if (await File('${root.path}/${entry.id}.${entry.kind.extension}')
              .exists()) {
            next.add(entry);
          }
        }
        _files
          ..clear()
          ..addAll(next);
        _sort();
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
  }

  void _sort() => _files.sort((a, b) => b.modified.compareTo(a.modified));
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
    if (!loaded || error != null) {
      throw StateError(error ?? 'История ещё загружается');
    }
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
    final next = [..._files.where((f) => f.id != entry.id), entry];
    await _writeIndex(root, next);
    _files
      ..clear()
      ..addAll(next);
    _sort();
    notifyListeners();
    return entry;
  });
  Future<void> toggleFavorite(WorkspaceFile file) => _serialize(() async {
    final next = _files
        .map((f) => f.id == file.id ? f.copyWith(favorite: !f.favorite) : f)
        .toList();
    await _writeIndex(await _root(), next);
    _files
      ..clear()
      ..addAll(next);
    notifyListeners();
  });
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
