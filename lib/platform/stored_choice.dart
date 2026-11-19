import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'application_storage.dart';

/// A small preference with a fixed set of persisted values.
class StoredChoice<T extends Object> extends ChangeNotifier {
  StoredChoice({
    required T initial,
    required this.fileName,
    required this.field,
    required this.options,
    this.directory,
    this.storage = const AndroidApplicationStorage(),
  }) : _value = initial;

  final String fileName, field;
  final Map<String, T> options;
  final Directory? directory;
  final ApplicationStorage storage;
  T _value;
  T get value => _value;
  int _revision = 0;
  bool _disposed = false;
  // A replacement screen can read a preference while its predecessor is saving.
  static Future<void> _writes = Future.value();

  Future<File> _file() async {
    final root = directory == null
        ? await storage.workspaceDirectory()
        : await directory!.create(recursive: true);
    return File('${root.path}/$fileName');
  }

  Future<void> load() async {
    final revision = _revision;
    await _writes;
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 1024) return;
      final data = jsonDecode(await file.readAsString());
      final saved = data is Map ? options[data[field]] : null;
      if (saved != null &&
          revision == _revision &&
          !_disposed &&
          saved != _value) {
        _value = saved;
        notifyListeners();
      }
    } catch (_) {
      // Keep the current choice if the preference is missing or damaged.
    }
  }

  Future<bool> select(T next) {
    final entry = options.entries.where((e) => e.value == next).firstOrNull;
    if (entry == null) throw ArgumentError.value(next);
    final revision = ++_revision;
    final changed = _value != next;
    _value = next;
    final write = _writes.then((_) async {
      if (revision != _revision) return true;
      try {
        final file = await _file();
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          jsonEncode({field: entry.key}),
          flush: true,
        );
        await temporary.rename(file.path);
        return true;
      } catch (_) {
        return false;
      }
    });
    _writes = write.then<void>((_) {});
    if (changed && !_disposed) notifyListeners();
    return write;
  }

  Future<void> flush() => _writes;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
