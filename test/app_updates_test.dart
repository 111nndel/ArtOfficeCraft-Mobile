import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:artofficecraft_mobile/l10n/app_strings.dart';
import 'package:artofficecraft_mobile/ui/update_panel.dart';
import 'package:artofficecraft_mobile/platform/application_storage.dart';
import 'package:artofficecraft_mobile/platform/app_update_installer.dart';
import 'package:artofficecraft_mobile/updates/app_updates.dart';
import 'package:artofficecraft_mobile/updates/update_source.dart';

UpdateRelease fixtureRelease() => UpdateRelease.fromJson({
  'tag': 'v0.53.0-alpha.1',
  'version': '0.53.0',
  'code': 2060,
  'size': 3,
  'hash': 'a' * 64,
  'url':
      'https://github.com/$updateRepository/releases/download/v0.53.0-alpha.1/ArtOfficeCraft-Mobile-0.53.0-arm64-preview.apk',
});

class FakeInstaller implements UpdateInstaller {
  FakeInstaller(this.directory);
  final Directory directory;
  int code = 2059, verifications = 0, installations = 0;
  bool reject = false;
  Completer<void>? pauseVerification;
  @override
  Future<InstalledApp> identity() async =>
      InstalledApp('0.52.0', code, 'arm64-v8a', directory);
  @override
  Future<void> verify(File file, String hash, int version) async {
    verifications++;
    await pauseVerification?.future;
    if (reject || version <= code || !await file.exists()) {
      throw StateError('APK rejected');
    }
  }

  @override
  Future<bool> install(File apk, String hash, int version) async {
    await verify(apk, hash, version);
    installations++;
    return true;
  }
}

class FakeSource implements UpdateSource {
  int checks = 0, downloads = 0, cancellations = 0;
  bool fail = false, truncate = false;
  UpdateRelease? candidate = fixtureRelease();
  Completer<UpdateRelease?>? pauseCheck;
  @override
  Future<UpdateRelease?> latest(InstalledApp current) async {
    checks++;
    if (fail) throw const SocketException('offline');
    return pauseCheck == null ? candidate : await pauseCheck!.future;
  }

  @override
  Future<void> download(
    UpdateRelease release,
    File file,
    void Function(int) progress,
  ) async {
    downloads++;
    if (fail) throw const SocketException('offline');
    await file.writeAsBytes(truncate ? [1] : [1, 2, 3]);
    progress(truncate ? 1 : 3);
  }

  @override
  void cancel() {
    cancellations++;
  }
}

void main() {
  late Directory root, cache;
  late FakeSource source;
  late FakeInstaller installer;
  late DateTime time;
  final owners = <AppUpdates>[];
  AppUpdates controller({FakeSource? backend}) {
    final instance = AppUpdates(
      storage: DirectoryApplicationStorage(root),
      installer: installer,
      source: backend ?? source,
      now: () => time,
    );
    owners.add(instance);
    return instance;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aoc-updates-');
    cache = await Directory('${root.path}/cache').create();
    installer = FakeInstaller(cache);
    source = FakeSource();
    time = DateTime.utc(2026, 11, 16);
  });
  tearDown(() async {
    for (final owner in owners) {
      await owner.flush();
      owner.dispose();
    }
    owners.clear();
    await root.delete(recursive: true);
  });

  test(
    'Manual is private by default; check and download are separate actions',
    () async {
      final updates = controller();
      await updates.load();
      expect(updates.automatic, false);
      expect(source.checks, 0);
      await updates.automaticCheck();
      expect(source.checks, 0);
      await updates.check();
      expect(updates.phase, UpdatePhase.available);
      expect(source.downloads, 0);
      expect(await updates.install(), false);
      await updates.download();
      expect(updates.phase, UpdatePhase.ready);
      expect(installer.verifications, 1);
      expect(await updates.install(), true);
      expect(installer.installations, 1);
      expect(installer.verifications, 2);
    },
  );

  test('Auto downloads once per day and cached verified update survives offline restart', () async {
    final updates = controller();
    await updates.load();
    await updates.selectAutomatic(true);
    expect(updates.phase, UpdatePhase.ready);
    expect(source.checks, 1);
    await updates.automaticCheck();
    expect(source.checks, 1);
    final offline = FakeSource()..fail = true;
    final restored = controller(backend: offline);
    await restored.load();
    expect(restored.automatic, true);
    expect(restored.phase, UpdatePhase.ready);
    expect(offline.checks, 0);
    time = time.add(const Duration(days: 1));
    await restored.automaticCheck();
    expect(offline.checks, 1);
    expect(restored.phase, UpdatePhase.ready);
    expect(await restored.install(), true);
    final again = controller(backend: FakeSource()..fail = true);
    await again.load();
    expect(again.phase, UpdatePhase.ready);
  });

  test('Manual mode persists after rapid changes and corrupted preferences stay offline', () async {
    source.candidate = null;
    final updates = controller();
    await updates.load();
    await Future.wait([
      updates.selectAutomatic(true),
      updates.selectAutomatic(false),
    ]);
    final restored = controller();
    await restored.load();
    expect(restored.automatic, false);
    final before = source.checks;
    await File('${root.path}/updates.json').writeAsString('{broken');
    await controller().load();
    expect(source.checks, before);
  });

  test(
    'Late automatic response is ignored after switching to manual',
    () async {
      source.pauseCheck = Completer<UpdateRelease?>();
      final updates = controller();
      await updates.load();
      final automatic = updates.selectAutomatic(true);
      while (source.checks == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await updates.selectAutomatic(false);
      source.pauseCheck!.complete(fixtureRelease());
      await automatic;
      expect(source.downloads, 0);
      expect(updates.release, null);
      expect(updates.phase, UpdatePhase.idle);
    },
  );

  test('Rejected and truncated APKs are never installed, partial files are removed', () async {
    final updates = controller();
    await updates.load();
    await updates.check();
    installer.reject = true;
    await updates.download();
    expect(updates.phase, UpdatePhase.failed);
    expect(await updates.install(), false);
    expect(await cache.list().toList(), isEmpty);
    installer.reject = false;
    source.truncate = true;
    final verified = installer.verifications;
    await updates.download();
    expect(installer.verifications, verified);
    expect(updates.phase, UpdatePhase.failed);
    expect(await cache.list().toList(), isEmpty);
    source.truncate = false;
    await updates.download();
    expect(updates.phase, UpdatePhase.ready);
  });

  test(
    'Cancel during native verification cannot publish a late ready APK',
    () async {
      final updates = controller();
      await updates.load();
      await updates.check();
      installer.pauseVerification = Completer<void>();
      final download = updates.download();
      while (installer.verifications == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      updates.cancel();
      installer.pauseVerification!.complete();
      await download;
      expect(updates.phase, UpdatePhase.available);
      expect(await File('${cache.path}/update.apk').exists(), false);
      expect(await cache.list().toList(), isEmpty);
    },
  );

  test('Cached tampering is rejected and an already installed version is cleaned up', () async {
    final updates = controller();
    await updates.load();
    await updates.check();
    await updates.download();
    installer.reject = true;
    final tampered = controller();
    await tampered.load();
    expect(tampered.phase, UpdatePhase.idle);
    expect(await File('${cache.path}/update.apk').exists(), false);
    installer.reject = false;
    await updates.download();
    installer.code = 2060;
    final newer = controller();
    await newer.load();
    expect(newer.phase, UpdatePhase.idle);
    expect(await File('${cache.path}/update.apk').exists(), false);
    expect(source.checks, 1);
  });

  test('Unchanged available release reuses the cached APK without downloading twice', () async {
    final updates = controller();
    await updates.load();
    await updates.selectAutomatic(true);
    await updates.automaticCheck(force: true);
    expect(updates.phase, UpdatePhase.ready);
    expect(source.downloads, 1);
    final saved = jsonDecode(
      await File('${root.path}/updates.json').readAsString(),
    ) as Map;
    expect(saved['pending']['code'], 2060);
  });

  testWidgets('Update status and mode have their own accessible labels', (
    tester,
  ) async {
    final updates = (await tester.runAsync(() async {
      final updates = controller();
      await updates.load().timeout(const Duration(seconds: 10));
      await updates.check().timeout(const Duration(seconds: 10));
      return updates;
    }))!;
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [AppStrings.delegate],
        home: Scaffold(
          body: SingleChildScrollView(child: UpdatePanel(updates: updates)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('update-status'))).label,
      'Version 0.53.0 is available',
    );
    final mode = tester.getSemantics(find.text('Manually')).label;
    expect(mode, contains('Manually'));
    expect(mode, isNot(contains('App updates')));
    await tester.tap(find.text('Manually'));
    await tester.pumpAndSettle();
    expect(find.text('Automatically'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
