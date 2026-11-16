import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/platform/app_update_installer.dart';
import 'package:artofficecraft_mobile/updates/update_source.dart';

class Headers implements HttpHeaders {
  Headers([this.values = const {}]);
  final Map<String, String> values;
  @override
  String? value(String name) => values[name];
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(
    List<List<int>> chunks, {
    this.statusCode = 200,
    int? length,
    Map<String, String> headers = const {},
  }) : _stream = Stream.fromIterable(chunks),
       contentLength = length ?? chunks.fold(0, (n, c) => n + c.length),
       headers = Headers(headers);
  Response.json(Object value) : this([utf8.encode(jsonEncode(value))]);
  final Stream<List<int>> _stream;
  @override
  final int statusCode, contentLength;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  final HttpHeaders headers = Headers();
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  Client(this.respond);
  final Response Function(Uri) respond;
  final requests = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    requests.add(uri);
    return Request(respond(uri));
  }

  @override
  set connectionTimeout(Duration? value) {}
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const version = '0.53.0', tag = 'v0.53.0-alpha.1';
  final url =
      'https://github.com/$updateRepository/releases/download/$tag/ArtOfficeCraft-Mobile-$version-arm64-preview.apk';
  final metaUrl =
      'https://github.com/$updateRepository/releases/download/$tag/build-info.json';
  Map<String, dynamic> descriptor() => {
    'tag': tag,
    'version': version,
    'code': 2060,
    'size': 3,
    'hash': 'a' * 64,
    'url': url,
  };
  Map<String, dynamic> metadata() => {
    'tag': tag,
    'version': version,
    'versionCode': 2060,
    'apk': 'ArtOfficeCraft-Mobile-$version-arm64-preview.apk',
    'sha256': 'a' * 64,
    'signingCertificateSha256': previewCertificate,
  };
  Map<String, dynamic> published() => {
    'draft': false,
    'prerelease': true,
    'tag_name': tag,
    'assets': [
      {'name': 'build-info.json', 'browser_download_url': metaUrl},
      {
        'name': 'ArtOfficeCraft-Mobile-$version-arm64-preview.apk',
        'browser_download_url': url,
        'size': 3,
        'digest': 'sha256:${'a' * 64}',
      },
    ],
  };
  final current = InstalledApp(
    '0.52.0',
    2059,
    'arm64-v8a',
    Directory.systemTemp,
  );

  test('Release parser rejects foreign URLs, schemes, unsafe identities and oversized APKs', () {
    expect(UpdateRelease.fromJson(descriptor()).code, 2060);
    for (final patch in [
      {'url': url.replaceFirst('https:', 'http:')},
      {'url': url.replaceFirst(updateRepository, 'attacker/fork')},
      {'url': '$url?token=value'},
      {'url': '$url#fragment'},
      {'hash': 'invalid'},
      {'size': 160 * 1024 * 1024 + 1},
      {'size': 0},
      {'code': -1},
      {'version': '0.52.0'},
      {'tag': '$tag/path'},
    ]) {
      expect(
        () => UpdateRelease.fromJson({...descriptor(), ...patch}),
        throwsFormatException,
      );
    }
  });

  test('Public prerelease is accepted only when metadata, APK digest and identity agree', () async {
    final client = Client(
      (uri) => uri.host == 'api.github.com'
          ? Response.json([published()])
          : Response.json(metadata()),
    );
    final source = GitHubUpdates(client: () => client);
    final release = await source.latest(current);
    expect(release?.code, 2060);
    expect(release?.uri.toString(), url);
    expect(client.requests.length, 2);
    for (final field in [
      'version',
      'tag',
      'apk',
      'signingCertificateSha256',
      'sha256',
    ]) {
      final damaged = {...metadata(), field: 'wrong'};
      final backend = GitHubUpdates(
        client: () => Client(
          (uri) => uri.host == 'api.github.com'
              ? Response.json([published()])
              : Response.json(damaged),
        ),
      );
      await expectLater(backend.latest(current), throwsFormatException);
    }
  });

  test(
    'Older/draft releases and unsupported ABI do not fetch APK metadata',
    () async {
      final client = Client(
        (_) => Response.json([
          {...published(), 'draft': true},
          {...published(), 'tag_name': 'v0.51.0-alpha.1'},
        ]),
      );
      final source = GitHubUpdates(client: () => client);
      expect(await source.latest(current), null);
      expect(client.requests.length, 1);
      expect(
        await source.latest(
          InstalledApp('0.52.0', 2059, 'x86_64', Directory.systemTemp),
        ),
        null,
      );
      expect(client.requests.length, 1);
      final same = GitHubUpdates(
        client: () => Client(
          (uri) => uri.host == 'api.github.com'
              ? Response.json([published()])
              : Response.json({...metadata(), 'versionCode': 2059}),
        ),
      );
      expect(await same.latest(current), null);
    },
  );

  test(
    'Unexpected redirects, HTTP failures and oversized metadata fail closed',
    () async {
      for (final target in [
        'http://github.com/file',
        'https://attacker.example/file',
        'https://localhost/file',
      ]) {
        final client = Client(
          (_) => Response([], statusCode: 302, headers: {'location': target}),
        );
        await expectLater(
          GitHubUpdates(client: () => client).latest(current),
          throwsFormatException,
        );
        expect(client.requests.length, 1);
      }
      await expectLater(
        GitHubUpdates(
          client: () => Client((_) => Response([], statusCode: 429)),
        ).latest(current),
        throwsA(isA<HttpException>()),
      );
      await expectLater(
        GitHubUpdates(
          client: () => Client((_) => Response([], length: 1024 * 1024 + 1)),
        ).latest(current),
        throwsFormatException,
      );
      final client = Client(
        (_) => Response(
          [],
          statusCode: 302,
          headers: {'location': 'https://github.com/repeat'},
        ),
      );
      await expectLater(
        GitHubUpdates(client: () => client).latest(current),
        throwsA(isA<HttpException>()),
      );
      expect(client.requests.length, 6);
    },
  );

  test('Streaming download accepts only exact size and reports progress without whole-file buffering', () async {
    final directory = await Directory.systemTemp.createTemp('aoc-download-');
    addTearDown(() => directory.delete(recursive: true));
    final release = UpdateRelease.fromJson(descriptor());
    final progress = <int>[];
    final good = GitHubUpdates(
      client: () => Client(
        (_) => Response([
          [1],
          [2, 3],
        ]),
      ),
    );
    final file = File('${directory.path}/update.part');
    await good.download(release, file, progress.add);
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(progress, [1, 3]);
    for (final chunks in [
      <List<int>>[
        [1],
      ],
      [
        [1, 2, 3, 4],
      ],
    ]) {
      final bad = GitHubUpdates(
        client: () => Client((_) => Response(chunks, length: -1)),
      );
      await expectLater(
        bad.download(release, file, (_) {}),
        throwsFormatException,
      );
    }
  });
}
