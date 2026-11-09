import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Platform-owned storage. Editors and settings never choose an OS directory.
abstract interface class ApplicationStorage {
  Future<Directory> workspaceDirectory();
  Future<String?> readReadingMode(String format);
  Future<void> writeReadingMode(String format, String mode);
}

/// Preserve the existing Android directory and preference keys during upgrades.
final class AndroidApplicationStorage implements ApplicationStorage {
  const AndroidApplicationStorage();
  static const _workspace = MethodChannel('artofficecraft/workspace');
  static const _reading = MethodChannel('artofficecraft/reading');

  @override
  Future<Directory> workspaceDirectory() async {
    final path = await _workspace.invokeMethod<String>('directory');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Application storage unavailable');
    }
    return Directory(path).create(recursive: true);
  }

  @override
  Future<String?> readReadingMode(String format) =>
      _reading.invokeMethod<String>('read', {'format': format});

  @override
  Future<void> writeReadingMode(String format, String mode) =>
      _reading.invokeMethod<void>('write', {'format': format, 'mode': mode});
}

/// Reusable on native desktop/iOS once the platform bootstrap supplies its
/// application support directory. Requires no plugin or network access.
final class DirectoryApplicationStorage implements ApplicationStorage {
  DirectoryApplicationStorage(this.directory);
  final Directory directory;
  Future<void> _writes = Future.value();

  @override
  Future<Directory> workspaceDirectory() => directory.create(recursive: true);

  Future<File> _readingFile(String format) async {
    if (!RegExp(r'^[a-z]{1,16}$').hasMatch(format)) {
      throw ArgumentError.value(format, 'format');
    }
    final root = await workspaceDirectory();
    return File('${root.path}/reading-$format.json');
  }

  @override
  Future<String?> readReadingMode(String format) async {
    await _writes;
    final file = await _readingFile(format);
    if (!await file.exists() || await file.length() > 1024) return null;
    final data = jsonDecode(await file.readAsString());
    return data is Map && data['mode'] is String ? data['mode'] as String : null;
  }

  @override
  Future<void> writeReadingMode(String format, String mode) {
    final write = _writes.then((_) async {
      final file = await _readingFile(format);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode({'mode': mode}), flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
