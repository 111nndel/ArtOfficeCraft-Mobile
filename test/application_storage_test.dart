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
}
