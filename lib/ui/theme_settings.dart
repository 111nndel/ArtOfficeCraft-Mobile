import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../platform/application_storage.dart';

/// Persist the explicit choice independently of the OS and document files.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings({
    this.directory,
    this.mode = ThemeMode.light,
    this.storage = const AndroidApplicationStorage(),
  });
  final Directory? directory;
  final ApplicationStorage storage;
  ThemeMode mode;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  Future<File> _file() async {
    final root = directory == null
        ? await storage.workspaceDirectory()
        : await directory!.create(recursive: true);
    return File('${root.path}/appearance.json');
  }

  Future<void> load() async {
    final revision = _revision;
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 1024) return;
      final data = jsonDecode(await file.readAsString());
      final name = data is Map ? data['theme'] : null;
      final values = ThemeMode.values.where((v) => v.name == name);
      if (values.isNotEmpty && revision == _revision && !_disposed) {
        mode = values.single;
        notifyListeners();
      }
    } catch (_) {
      // A missing/damaged preference must not prevent opening the app.
    }
  }

  Future<bool> select(ThemeMode value) {
    mode = value;
    final revision = ++_revision;
    if (!_disposed) notifyListeners();
    final next = _writes.then((_) async {
      try {
        if (revision != _revision) return true;
        final file = await _file();
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(jsonEncode({'theme': value.name}), flush: true);
        await tmp.rename(file.path);
        return true;
      } catch (_) {
        return false;
      }
    });
    _writes = next.then<void>((_) {});
    return next;
  }

  Future<void> flush() => _writes;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
