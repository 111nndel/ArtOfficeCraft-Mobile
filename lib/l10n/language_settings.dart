import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LanguageSettings extends ChangeNotifier {
  LanguageSettings({this.directory, String initial = 'system'})
    : language = initial;
  final Directory? directory;
  String language;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static const choices = ['system', 'ru', 'en'];
  Locale? get locale => language == 'system' ? null : Locale(language);
  Future<File> _file() async {
    final path =
        directory?.path ??
        await const MethodChannel('artofficecraft/workspace')
            .invokeMethod<String>('directory');
    if (path == null) throw const FileSystemException('Settings unavailable');
    final root = await Directory(path).create(recursive: true);
    return File('${root.path}/language.json');
  }

  Future<void> load() async {
    final revision = _revision;
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 1024) return;
      final data = jsonDecode(await file.readAsString());
      final value = data is Map ? data['language'] : null;
      if (choices.contains(value) && revision == _revision) {
        language = value as String;
        _notify();
      }
    } catch (_) {
      /* System language remains usable without a saved preference. */
    }
  }

  Future<bool> select(String value) {
    if (!choices.contains(value)) throw ArgumentError.value(value);
    language = value;
    final revision = ++_revision;
    _notify();
    final next = _writes.then((_) async {
      try {
        if (revision != _revision) return true;
        final file = await _file();
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          jsonEncode({'language': value}),
          flush: true,
        );
        await temporary.rename(file.path);
        return true;
      } catch (_) {
        return false;
      }
    });
    _writes = next.then<void>((_) {});
    return next;
  }
}

class LanguageScope extends InheritedNotifier<LanguageSettings> {
  const LanguageScope({
    super.key,
    required LanguageSettings settings,
    required super.child,
  }) : super(notifier: settings);
  static LanguageSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
}
