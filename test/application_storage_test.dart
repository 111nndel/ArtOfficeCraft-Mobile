import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/l10n/language_settings.dart';
import 'package:artofficecraft_mobile/platform/application_storage.dart';
import 'package:artofficecraft_mobile/ui/page_reading.dart';
import 'package:artofficecraft_mobile/ui/theme_settings.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('One portable storage restores settings, recents and recovery', () async {
    final root = await Directory.systemTemp.createTemp('aoc-platform-');
    addTearDown(() => root.delete(recursive: true));
    final storage = DirectoryApplicationStorage(root);
    final theme = ThemeSettings(storage: storage);
    final language = LanguageSettings(storage: storage);
    final workspace = WorkspaceStore(storage: storage);
    final drafts = DraftStore(storage: storage);
    for (final notifier in [theme, language, workspace, drafts]) {
      addTearDown(notifier.dispose);
    }
    expect(await theme.select(ThemeMode.dark), isTrue);
    expect(await language.select('en'), isTrue);
    await workspace.load();
    expect(workspace.error, isNull);
    final bytes = Uint8List.fromList([80, 75, 3, 4, 1]);
    final file = await workspace.remember(EditorKind.excel, bytes, 'Budget.xlsx');
    const id = 'r0123456789abcdef0123456789abcdef';
    await drafts.write(
      id: id,
      kind: EditorKind.excel,
      name: file.name,
      bytes: bytes,
      editor: {'cell': 'B2', 'input': 'unsaved'},
      workspaceId: file.id,
    );
    await storage.writeReadingMode('pdf', ReadingMode.continuous.name);
    await storage.writeReadingMode('deck', ReadingMode.vertical.name);

    final restarted = DirectoryApplicationStorage(Directory(root.path));
    final nextTheme = ThemeSettings(storage: restarted);
    final nextLanguage = LanguageSettings(storage: restarted);
    final nextWorkspace = WorkspaceStore(storage: restarted);
    final nextDrafts = DraftStore(storage: restarted);
    final pdf = ReadingModePreference('pdf', storage: restarted);
    final deck = ReadingModePreference('deck', storage: restarted);
    for (final notifier in [
      nextTheme, nextLanguage, nextWorkspace, nextDrafts, pdf, deck,
    ]) {
      addTearDown(notifier.dispose);
    }
    await Future.wait([
      nextTheme.load(), nextLanguage.load(), nextWorkspace.load(),
      nextDrafts.load(), pdf.load(), deck.load(),
    ]);
    expect(nextTheme.mode, ThemeMode.dark);
    expect(nextLanguage.language, 'en');
    expect(await nextWorkspace.read(nextWorkspace.files.single), bytes);
    final recovered = await nextDrafts.read(id);
    expect(recovered.bytes, bytes);
    expect(recovered.info.workspaceId, file.id);
    expect(recovered.editor['input'], 'unsaved');
    expect(pdf.value, ReadingMode.continuous);
    expect(deck.value, ReadingMode.vertical);
  });

  test('Reading writes are ordered; invalid paths cannot escape storage', () async {
    final root = await Directory.systemTemp.createTemp('aoc-reading-storage-');
    addTearDown(() => root.delete(recursive: true));
    final storage = DirectoryApplicationStorage(root);
    await expectLater(
      storage.writeReadingMode('../outside', 'horizontal'),
      throwsArgumentError,
    );
    await Future.wait([
      storage.writeReadingMode('pdf', 'vertical'),
      storage.writeReadingMode('pdf', 'continuous'),
      storage.writeReadingMode('deck', 'horizontal'),
    ]);
    expect(await storage.readReadingMode('pdf'), 'continuous');
    expect(await storage.readReadingMode('deck'), 'horizontal');
    expect(root.listSync().whereType<File>(), hasLength(2));
  });
  test(
    'Android legacy modes survive; new files win across storage instances',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aoc-reading-upgrade-',
      );
      addTearDown(() => root.delete(recursive: true));
      const workspace = MethodChannel('artofficecraft/workspace');
      const reading = MethodChannel('artofficecraft/reading');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final legacy = {'pdf': 'continuous', 'deck': 'vertical'};
      var reads = 0;
      messenger.setMockMethodCallHandler(workspace, (call) async {
        expect(call.method, 'directory');
        return root.path;
      });
      messenger.setMockMethodCallHandler(reading, (call) async {
        expect(call.method, 'read');
        reads++;
        return legacy[(call.arguments as Map)['format']];
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(workspace, null);
        messenger.setMockMethodCallHandler(reading, null);
      });
      final first = AndroidApplicationStorage();
      final second = AndroidApplicationStorage();
      final portable = DirectoryApplicationStorage(root);
      expect(await first.readReadingMode('pdf'), 'continuous');
      expect(await second.readReadingMode('deck'), 'vertical');
      expect(root.listSync(), isEmpty);
      await Future.wait([
        first.writeReadingMode('pdf', 'horizontal'),
        second.writeReadingMode('pdf', 'vertical'),
        portable.writeReadingMode('pdf', 'continuous'),
        second.writeReadingMode('deck', 'horizontal'),
      ]);
      final reopened = AndroidApplicationStorage();
      expect(await reopened.readReadingMode('pdf'), 'continuous');
      expect(await reopened.readReadingMode('deck'), 'horizontal');
      expect(await portable.readReadingMode('deck'), 'horizontal');
      expect(
        jsonDecode(await File('${root.path}/reading-deck.json').readAsString()),
        {'mode': 'horizontal'},
      );
      expect(reads, 2);
      expect(legacy, {'pdf': 'continuous', 'deck': 'vertical'});
      await File('${root.path}/reading-pdf.json').writeAsString('{broken');
      await expectLater(reopened.readReadingMode('pdf'), throwsFormatException);
      expect(
        reads,
        2,
      ); // A damaged new file cannot revive an obsolete preference.
    },
  );

  test(
    'Failed reading writes preserve the last mode and do not poison the queue',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aoc-reading-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = DirectoryApplicationStorage(root);
      final second = DirectoryApplicationStorage(root);
      await first.writeReadingMode('pdf', 'horizontal');
      await expectLater(
        second.writeReadingMode('pdf', 'invalid'),
        throwsArgumentError,
      );
      final obstruction = await Directory('${root.path}/reading-pdf.json.tmp')
          .create();
      await expectLater(
        second.writeReadingMode('pdf', 'vertical'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await first.readReadingMode('pdf'), 'horizontal');
      await obstruction.delete();
      await second.writeReadingMode('pdf', 'continuous');
      expect(await first.readReadingMode('pdf'), 'continuous');
    },
  );
}
