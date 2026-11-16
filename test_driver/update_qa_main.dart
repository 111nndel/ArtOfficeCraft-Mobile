// QA entry point only. Normal APKs always compile lib/main.dart.
import 'dart:io';

import 'package:artofficecraft_mobile/main.dart';
import 'package:artofficecraft_mobile/platform/app_update_installer.dart';
import 'package:artofficecraft_mobile/updates/app_updates.dart';
import 'package:artofficecraft_mobile/updates/update_source.dart';
import 'package:flutter/widgets.dart';

// Keep the production URL/redirect/metadata parser. Route its HTTPS requests to
// a disposable local fixture server; this adapter is absent from the public APK.
class FixtureClient implements HttpClient {
  final HttpClient client = HttpClient()
    ..userAgent = 'aoc-update-fixture-only'
    ..badCertificateCallback = (certificate, host, port) =>
        host == '10.0.2.2' && port == 8765;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) => client.getUrl(
    Uri(
      scheme: 'https',
      host: '10.0.2.2',
      port: 8765,
      path: uri.path,
      query: uri.query,
    ),
  );
  @override
  set connectionTimeout(Duration? value) {
    client.connectionTimeout = value;
  }

  @override
  void close({bool force = false}) {
    client.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FixtureInstaller extends AndroidUpdateInstaller {
  @override
  Future<InstalledApp> identity() async {
    final actual = await super.identity();
    // Catalog assets are labelled ARM64. The real Android verifier still checks
    // the fixture APK's x86_64 libraries against the actual emulator ABI.
    return InstalledApp(
      actual.version,
      actual.code,
      'arm64-v8a',
      actual.directory,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final updates = AppUpdates(
    installer: FixtureInstaller(),
    source: GitHubUpdates(client: FixtureClient.new),
  );
  await updates.load();
  runApp(ArtOfficeCraftApp(initialLanguage: 'en', updates: updates));
}
