import 'dart:io';

import 'package:flutter/services.dart';

class InstalledApp {
  const InstalledApp(this.version, this.code, this.abi, this.directory);
  final String version, abi;
  final int code;
  final Directory directory;
}

abstract interface class UpdateInstaller {
  Future<InstalledApp> identity();
  Future<void> verify(File apk, String sha256, int versionCode);
  Future<bool> install(File apk, String sha256, int versionCode);
}

/// Android owns package signatures, URI grants and the system installer.
class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller();
  static const channel = MethodChannel('artofficecraft/app_updates');
  @override
  Future<InstalledApp> identity() async {
    final data = (await channel.invokeMapMethod<String, dynamic>('identity'))!;
    return InstalledApp(
      data['version'] as String,
      data['code'] as int,
      data['abi'] as String,
      Directory(data['directory'] as String),
    );
  }

  Map<String, Object> _args(File apk, String hash, int code) => {
    'path': apk.path,
    'sha256': hash,
    'code': code,
  };
  @override
  Future<void> verify(File apk, String sha256, int versionCode) =>
      channel.invokeMethod<void>('verify', _args(apk, sha256, versionCode));
  @override
  Future<bool> install(File apk, String sha256, int versionCode) async =>
      await channel.invokeMethod<bool>(
        'install',
        _args(apk, sha256, versionCode),
      ) ??
      false;
}
