import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Platform-owned storage. Editors and settings never choose an OS directory.
abstract interface class ApplicationStorage {
  Future<Directory> workspaceDirectory();
  Future<String?> readReadingMode(String format);
  Future<void> writeReadingMode(String format, String mode);
}

/// Android supplies its private directory and reads pre-file reading preferences.
final class AndroidApplicationStorage with _ReadingModeFiles {
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
  Future<String?> _legacyReadingMode(String format) =>
      format == 'pdf' || format == 'deck'
      ? _reading.invokeMethod<String>('read', {'format': format})
      : Future.value(null);
}

/// Reusable on native desktop/iOS once the platform bootstrap supplies its
/// application support directory. Requires no plugin or network access.
final class DirectoryApplicationStorage with _ReadingModeFiles {
  DirectoryApplicationStorage(this.directory);
  final Directory directory;

  @override
  Future<Directory> workspaceDirectory() => directory.create(recursive: true);
}

/// All adapters share file semantics and ordering, including distinct const
/// Android adapters writing to the same private directory.
mixin _ReadingModeFiles implements ApplicationStorage {
  static Future<void> _writes = Future.value();

  Future<String?> _legacyReadingMode(String format) async => null;

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
    if (!await file.exists()) return _legacyReadingMode(format);
    if (await file.length() > 1024) return null;
    final data = jsonDecode(await file.readAsString());
    return data is Map && data['mode'] is String
        ? data['mode'] as String
        : null;
  }

  @override
  Future<void> writeReadingMode(String format, String mode) {
    final write = _writes.then((_) async {
      if (!const {'horizontal', 'vertical', 'continuous'}.contains(mode)) {
        throw ArgumentError.value(mode, 'mode');
      }
      final file = await _readingFile(format);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode({'mode': mode}), flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
