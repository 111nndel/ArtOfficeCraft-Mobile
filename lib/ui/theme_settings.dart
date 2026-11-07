import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Persist the explicit choice independently of the OS and document files.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings({this.directory, this.mode = ThemeMode.light});
  final Directory? directory;
  ThemeMode mode;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  Future<File> _file() async {
    final path =
        directory?.path ??
        await const MethodChannel('artofficecraft/workspace')
            .invokeMethod<String>('directory');
    if (path == null) throw const FileSystemException('Settings unavailable');
    final root = await Directory(path).create(recursive: true);
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
