import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/app_update_installer.dart';

const updateRepository = '111nndel/ArtOfficeCraft-Mobile';
const previewCertificate =
    '4e16cc21d19cdcde840361cd34fbdcfbf901b48c6f8ff66ef473e7ddf4a05005';

class UpdateRelease {
  UpdateRelease.fromJson(Map<String, dynamic> data)
    : tag = data['tag'] as String,
      version = data['version'] as String,
      code = data['code'] as int,
      size = data['size'] as int,
      hash = data['hash'] as String,
      uri = Uri.parse(data['url'] as String) {
    if (!RegExp('^v${RegExp.escape(version)}-alpha\\.[0-9]+\$').hasMatch(tag) ||
        !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
        code < 1 ||
        code > 2100000000 ||
        size < 1 ||
        size > 160 * 1024 * 1024 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path !=
            '/$updateRepository/releases/download/$tag/ArtOfficeCraft-Mobile-$version-arm64-preview.apk') {
      throw const FormatException('Invalid update release');
    }
  }
  final String tag, version, hash;
  final int code, size;
  final Uri uri;
  Map<String, dynamic> toJson() => {
    'tag': tag,
    'version': version,
    'code': code,
    'size': size,
    'hash': hash,
    'url': uri.toString(),
  };
}

abstract interface class UpdateSource {
  Future<UpdateRelease?> latest(InstalledApp current);
  Future<void> download(
    UpdateRelease release,
    File destination,
    void Function(int bytes) progress,
  );
  void cancel();
}

/// Only public GitHub release metadata and its APK assets are requested.
class GitHubUpdates implements UpdateSource {
  GitHubUpdates({HttpClient Function()? client})
    : _create = client ?? HttpClient.new;
  final HttpClient Function() _create;
  HttpClient? _client;
  int _epoch = 0;
  @override
  void cancel() {
    _epoch++;
    _client?.close(force: true);
    _client = null;
  }

  Future<HttpClientResponse> _open(Uri uri) async {
    final epoch = _epoch;
    final client = _client ??= _create()
      ..connectionTimeout = const Duration(seconds: 15);
    for (var hop = 0; hop < 6; hop++) {
      if (uri.scheme != 'https' ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          !const {
            'api.github.com',
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        throw const FormatException('Unexpected update host');
      }
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ArtOfficeCraft-Mobile-Updater',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (epoch != _epoch) throw const HttpException('Update cancelled');
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>().timeout(const Duration(seconds: 15));
        if (location == null) throw const HttpException('Missing redirect');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub HTTP ${response.statusCode}');
      }
      return response;
    }
    throw const HttpException('Too many update redirects');
  }

  Future<dynamic> _json(Uri uri) async {
    final response = await _open(uri);
    if (response.contentLength > 1024 * 1024) {
      throw const FormatException('Update metadata too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('Update metadata too large');
      }
      bytes.add(chunk);
    }
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  }

  @override
  Future<UpdateRelease?> latest(InstalledApp current) async {
    if (current.abi != 'arm64-v8a') return null;
    final catalog = await _json(
      Uri.https('api.github.com', '/repos/$updateRepository/releases', {
        'per_page': '10',
      }),
    );
    if (catalog is! List) {
      throw const FormatException('Invalid release catalog');
    }
    for (final item in catalog.whereType<Map>()) {
      if (item['draft'] != false) continue;
      final tag = item['tag_name'];
      if (tag is! String) continue;
      final match = RegExp(r'^v([0-9]+\.[0-9]+\.[0-9]+)-alpha\.[0-9]+$')
          .firstMatch(tag);
      if (match == null) continue;
      final version = match[1]!;
      final candidateParts = version.split('.').map(int.parse).toList();
      final installedParts = current.version
          .split('.')
          .map(int.tryParse)
          .toList();
      if (installedParts.length == 3 &&
          installedParts.every((n) => n != null)) {
        final different = List.generate(
          3,
          (i) => i,
        ).where((i) => candidateParts[i] != installedParts[i]).firstOrNull;
        if (different != null &&
            candidateParts[different] < installedParts[different]!) {
          continue;
        }
      }
      final assets = item['assets'];
      if (assets is! List) continue;
      final apkName = 'ArtOfficeCraft-Mobile-$version-arm64-preview.apk';
      final apk = assets
          .whereType<Map>()
          .where((a) => a['name'] == apkName)
          .firstOrNull;
      final meta = assets
          .whereType<Map>()
          .where((a) => a['name'] == 'build-info.json')
          .firstOrNull;
      if (apk == null || meta == null) continue;
      final metadataUrl = Uri.parse(meta['browser_download_url'] as String);
      if (metadataUrl.toString() !=
          'https://github.com/$updateRepository/releases/download/$tag/build-info.json') {
        throw const FormatException('Unexpected update metadata URL');
      }
      final info = await _json(metadataUrl);
      if (info is! Map ||
          info['version'] != version ||
          info['tag'] != tag ||
          info['apk'] != apkName ||
          info['signingCertificateSha256'] != previewCertificate) {
        throw const FormatException('Release identity mismatch');
      }
      final release = UpdateRelease.fromJson({
        'tag': tag,
        'version': version,
        'code': info['versionCode'],
        'size': apk['size'],
        'hash': info['sha256'],
        'url': apk['browser_download_url'],
      });
      if (apk['digest'] != null && apk['digest'] != 'sha256:${release.hash}') {
        throw const FormatException('Release checksum mismatch');
      }
      if (release.code > current.code) return release;
    }
    return null;
  }

  @override
  Future<void> download(
    UpdateRelease release,
    File destination,
    void Function(int bytes) progress,
  ) async {
    final response = await _open(release.uri);
    if (response.contentLength >= 0 && response.contentLength != release.size) {
      throw const FormatException('APK length mismatch');
    }
    final output = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > release.size) {
          throw const FormatException('APK exceeds expected size');
        }
        output.add(chunk);
        progress(received);
        // Apply backpressure instead of buffering a whole APK on a slow device.
        await output.flush();
      }
      await output.flush();
      if (received != release.size) {
        throw const FormatException('Incomplete APK');
      }
    } finally {
      await output.close();
    }
  }
}
