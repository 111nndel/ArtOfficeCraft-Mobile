import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/application_storage.dart';
import '../platform/app_update_installer.dart';
import 'update_source.dart';

enum UpdatePhase { idle, checking, available, downloading, ready, failed }

class AppUpdates extends ChangeNotifier {
  AppUpdates({
    this.storage = const AndroidApplicationStorage(),
    this.installer = const AndroidUpdateInstaller(),
    UpdateSource? source,
    DateTime Function()? now,
  }) : source = source ?? GitHubUpdates(),
       now = now ?? DateTime.now;
  final ApplicationStorage storage;
  final UpdateInstaller installer;
  final UpdateSource source;
  final DateTime Function() now;
  InstalledApp? installed;
  UpdateRelease? release;
  UpdatePhase phase = UpdatePhase.idle;
  bool automatic = false,
      loaded = false,
      checked = false,
      preferenceError = false;
  bool installing = false;
  int received = 0;
  DateTime? checkedAt;
  bool _disposed = false, _downloaded = false;
  int _generation = 0, _preferenceRevision = 0;
  Future<void> _writes = Future.value();
  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;
  File get _apk => File('${installed!.directory.path}/update.apk');
  bool _valid(int token) => !_disposed && token == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<File> _preferences() async =>
      File('${(await storage.workspaceDirectory()).path}/updates.json');

  Future<void> load() async {
    final revision = _preferenceRevision;
    Map? data;
    try {
      final file = await _preferences();
      if (await file.exists() && await file.length() <= 8192) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) data = decoded;
      }
    } catch (_) {
      /* A damaged preference keeps manual mode usable. */
    }
    if (_disposed) return;
    if (revision == _preferenceRevision) {
      automatic = data?['automatic'] == true;
      final stamp = data?['checkedAt'];
      if (stamp is int && stamp >= 0 && stamp <= now().millisecondsSinceEpoch) {
        checkedAt = DateTime.fromMillisecondsSinceEpoch(stamp);
      }
    }
    try {
      installed = await installer.identity();
    } catch (_) {
      /* Non-Android host. */
    }
    if (_disposed) return;
    final pending = data?['pending'];
    if (installed != null) {
      try {
        if (pending is Map) {
          final saved = UpdateRelease.fromJson(
            Map<String, dynamic>.from(pending),
          );
          if (saved.code > installed!.code &&
              await _apk.exists() &&
              await _apk.length() == saved.size) {
            await installer.verify(_apk, saved.hash, saved.code);
            if (_disposed) return;
            release = saved;
            _downloaded = true;
            phase = UpdatePhase.ready;
          }
        }
        if (phase != UpdatePhase.ready && await _apk.exists()) {
          await _apk.delete();
        }
        await for (final entry in installed!.directory.list()) {
          if (entry is File &&
              RegExp(r'^update-[0-9]+\.part$')
                  .hasMatch(entry.uri.pathSegments.last)) {
            await entry.delete();
          }
        }
      } catch (_) {
        release = null;
        _downloaded = false;
        phase = UpdatePhase.idle;
        try {
          if (await _apk.exists()) await _apk.delete();
        } catch (_) {
          /* Cache may be unavailable. */
        }
      }
    }
    if (_disposed) return;
    loaded = true;
    _notify();
    await automaticCheck();
  }

  Future<void> _save() {
    final contents = jsonEncode({
      'automatic': automatic,
      'checkedAt': checkedAt?.millisecondsSinceEpoch,
      if (_downloaded && release != null) 'pending': release!.toJson(),
    });
    final next = _writes.then((_) async {
      try {
        final file = await _preferences();
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(contents, flush: true);
        await tmp.rename(file.path);
        preferenceError = false;
      } catch (_) {
        preferenceError = true;
      }
      _notify();
    });
    _writes = next;
    return next;
  }

  Future<void> selectAutomatic(bool enabled) async {
    _preferenceRevision++;
    automatic = enabled;
    if (!enabled && busy) {
      _generation++;
      source.cancel();
      phase = _downloaded
          ? UpdatePhase.ready
          : release == null
          ? UpdatePhase.idle
          : UpdatePhase.available;
    }
    _notify();
    await _save();
    if (enabled) await automaticCheck(force: true);
  }

  Future<void> automaticCheck({bool force = false}) async {
    if (!loaded ||
        !automatic ||
        busy ||
        installing ||
        _disposed ||
        installed == null)
      return;
    if (!force &&
        checkedAt != null &&
        now().difference(checkedAt!) < const Duration(days: 1)) {
      return;
    }
    await check(downloadAutomatically: true);
  }

  Future<void> check({bool downloadAutomatically = false}) async {
    if (!loaded || installed == null || busy || installing || _disposed) return;
    final token = ++_generation;
    final wasReady = _downloaded;
    phase = UpdatePhase.checking;
    checkedAt = now();
    _notify();
    await _save();
    if (!_valid(token)) return;
    try {
      final found = await source.latest(installed!);
      if (!_valid(token)) return;
      checked = true;
      if (wasReady &&
          found != null &&
          release?.code == found.code &&
          release?.hash == found.hash) {
        phase = UpdatePhase.ready;
      } else {
        _downloaded = false;
        release = found;
        phase = found == null ? UpdatePhase.idle : UpdatePhase.available;
        if (found != null && downloadAutomatically && automatic) {
          await _download(token, found);
        }
      }
    } catch (_) {
      if (_valid(token)) {
        phase = _downloaded ? UpdatePhase.ready : UpdatePhase.failed;
      }
    } finally {
      if (_valid(token)) {
        source.cancel();
        await _save();
        _notify();
      }
    }
  }

  Future<void> download() async {
    if (release == null || installed == null || busy || installing || _disposed)
      return;
    final token = ++_generation;
    try {
      await _download(token, release!);
    } catch (_) {
      if (_valid(token)) phase = UpdatePhase.failed;
    } finally {
      if (_valid(token)) {
        source.cancel();
        await _save();
        _notify();
      }
    }
  }

  Future<void> _download(int token, UpdateRelease item) async {
    phase = UpdatePhase.downloading;
    received = 0;
    _notify();
    final temporary = File('${installed!.directory.path}/update-$token.part');
    try {
      await source.download(item, temporary, (bytes) {
        if (_valid(token) &&
            (bytes - received >= 256 * 1024 || bytes == item.size)) {
          received = bytes;
          _notify();
        }
      });
      if (!_valid(token)) return;
      if (await temporary.length() != item.size) {
        throw const FormatException('Incomplete update');
      }
      await installer.verify(temporary, item.hash, item.code);
      if (!_valid(token)) return;
      await temporary.rename(_apk.path);
      if (!_valid(token)) return;
      _downloaded = true;
      phase = UpdatePhase.ready;
      await _save();
      _notify();
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<bool> install() async {
    if (phase != UpdatePhase.ready ||
        release == null ||
        installed == null ||
        installing) {
      return false;
    }
    installing = true;
    _notify();
    try {
      // Recheck after every restart and immediately before the Android handoff.
      return await installer.install(_apk, release!.hash, release!.code);
    } catch (_) {
      _downloaded = false;
      phase = UpdatePhase.failed;
      await _save();
      _notify();
      return false;
    } finally {
      installing = false;
      _notify();
    }
  }

  void cancel() {
    if (!busy) return;
    _generation++;
    source.cancel();
    phase = _downloaded
        ? UpdatePhase.ready
        : release == null
        ? UpdatePhase.idle
        : UpdatePhase.available;
    _notify();
  }

  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    source.cancel();
    super.dispose();
  }
}
