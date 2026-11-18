import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Local copy and favorite survive restart; updates keep stable identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-workspace-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = WorkspaceStore(directory: directory);
      await store.load();
      final first = await store.remember(
        EditorKind.word,
        Uint8List.fromList([1, 2, 3]),
        'Проект.docx',
      );
      await store.toggleFavorite(first);
      final updated = await store.remember(
        EditorKind.word,
        Uint8List.fromList([4, 5]),
        'Обновлённый.docx',
        id: first.id,
      );
      expect(updated.id, first.id);
      expect(updated.favorite, isTrue);
      final restored = WorkspaceStore(directory: directory);
      await restored.load();
      expect(restored.files, hasLength(1));
      expect(restored.files.single.name, 'Обновлённый.docx');
      expect(restored.files.single.favorite, isTrue);
      expect(await restored.read(restored.files.single), [4, 5]);
    },
  );
  test(
    'Concurrent imports retain both records and only private paths are used',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-queue-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = WorkspaceStore(directory: directory);
      await store.load();
      await Future.wait([
        store.remember(
          EditorKind.word,
          Uint8List.fromList([1]),
          '../../Document.docx',
        ),
        store.remember(EditorKind.pdf, Uint8List.fromList([2]), 'PDF.pdf'),
      ]);
      final restored = WorkspaceStore(directory: directory);
      await restored.load();
      expect(restored.files, hasLength(2));
      expect(restored.files.map((f) => f.id).toSet(), hasLength(2));
      expect(directory.listSync().whereType<File>().length, 3);
    },
  );
  for (final kind in EditorKind.values) {
    test(
      'Opening another ${kind.name} document preserves previous recents after restart',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'aoc-switch-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final store = WorkspaceStore(directory: directory);
        await store.load();
        final session = WorkspaceDocumentSession(store, kind);
        await session.remember(
          Uint8List.fromList([1]),
          'First.${kind.extension}',
        );
        final first = session.id;
        await store.toggleFavorite(store.files.single);
        session.startDocument();
        // Same filenames can be different imports; names are not file identities.
        await session.remember(
          Uint8List.fromList([2]),
          'First.${kind.extension}',
        );
        final second = session.id;
        expect(second, isNot(first));
        await session.remember(
          Uint8List.fromList([3]),
          'Saved copy.${kind.extension}',
        );
        expect(session.id, second);
        final restored = WorkspaceStore(directory: directory);
        await restored.load();
        expect(restored.files, hasLength(2));
        final old = restored.files.singleWhere((f) => f.id == first);
        final updated = restored.files.singleWhere((f) => f.id == second);
        expect(await restored.read(old), [1]);
        expect(old.favorite, true);
        expect(await restored.read(updated), [3]);
        expect(updated.name, 'Saved copy.${kind.extension}');
      },
    );
  }

  test(
    'Legacy history remains recent and hiding keeps copies after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp('aoc-history-');
      addTearDown(() => directory.delete(recursive: true));
      final store = WorkspaceStore(directory: directory);
      await store.load();
      final first = await store.remember(
        EditorKind.word,
        Uint8List.fromList([1]),
        'First.docx',
      );
      final second = await store.remember(
        EditorKind.pdf,
        Uint8List.fromList([2]),
        'Second.pdf',
      );
      await store.toggleFavorite(first);
      final index = File('${directory.path}/index.json');
      final legacy = (jsonDecode(await index.readAsString()) as List)
          .map(
            (value) =>
                (Map<String, dynamic>.from(value as Map)..remove('recent')),
          )
          .toList();
      await index.writeAsString(jsonEncode(legacy));
      final restored = WorkspaceStore(directory: directory);
      await restored.load();
      expect(restored.files.every((f) => f.recent), isTrue);
      final before = restored.files
          .map((f) => f.toJson()..remove('recent'))
          .toList();
      expect(await restored.setRecent([first.id], false), {first.id});
      expect(
        restored.files.singleWhere((f) => f.id == second.id).recent,
        isTrue,
      );
      await restored.setRecent(restored.files.map((f) => f.id), false);
      final reopened = WorkspaceStore(directory: directory);
      await reopened.load();
      expect(reopened.files.every((f) => !f.recent), isTrue);
      expect(
        reopened.files.map((f) => f.toJson()..remove('recent')).toList(),
        before,
      );
      expect(await reopened.read(first), [1]);
      expect(await reopened.read(second), [2]);
      expect(
        reopened.files.singleWhere((f) => f.id == first.id).favorite,
        isTrue,
      );
    },
  );

  test(
    'Queued history and undo preserve newer favorites and document changes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-history-queue-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = WorkspaceStore(directory: directory);
      await store.load();
      final first = await store.remember(
        EditorKind.excel,
        Uint8List.fromList([1]),
        'First.xlsx',
      );
      final second = await store.remember(
        EditorKind.pdf,
        Uint8List.fromList([2]),
        'Second.pdf',
      );
      final selected = {first.id};
      final removal = store.setRecent(selected, false);
      selected
        ..clear()
        ..add(second.id);
      final favorite = store.toggleFavorite(first);
      final removed = await removal;
      await favorite;
      expect(removed, {first.id});
      expect(store.files.singleWhere((f) => f.id == second.id).recent, isTrue);
      final updated = await store.remember(
        EditorKind.excel,
        Uint8List.fromList([3, 4]),
        'Renamed.xlsx',
        id: first.id,
      );
      expect(updated.recent, isTrue);
      expect(updated.favorite, isTrue);
      await store.setRecent(removed, true);
      expect(store.files, hasLength(2));
      expect(
        store.files.singleWhere((f) => f.id == first.id).name,
        'Renamed.xlsx',
      );
      expect(await store.read(updated), [3, 4]);
      await store.setRecent([first.id], false);
      await store.toggleFavorite(updated);
      await store.setRecent([first.id], true);
      expect(
        store.files.singleWhere((f) => f.id == first.id).favorite,
        isFalse,
      );
    },
  );

  test(
    'Failed atomic history writes retain the list and allow a retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-history-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = WorkspaceStore(directory: directory);
      await store.load();
      final entry = await store.remember(
        EditorKind.pdf,
        Uint8List.fromList([7]),
        'Kept.pdf',
      );
      final index = File('${directory.path}/index.json');
      final before = await index.readAsString();
      final blocker = await Directory('${index.path}.tmp').create();
      await expectLater(
        store.setRecent([entry.id], false),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.files.single.recent, isTrue);
      expect(await index.readAsString(), before);
      expect(await store.read(entry), [7]);
      await blocker.delete();
      await store.setRecent([entry.id], false);
      expect(store.files.single.recent, isFalse);
    },
  );

  test(
    'Damaged index is preserved and cannot be silently overwritten',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-index-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final index = File('${directory.path}/index.json');
      final store = WorkspaceStore(directory: directory);
      await store.load();
      final file = await store.remember(
        EditorKind.word,
        Uint8List.fromList([9]),
        'Kept.docx',
      );
      final snapshot = store.files;
      await index.writeAsString('[broken');
      await store.load();
      expect(store.error, isNotNull);
      expect(store.files, same(snapshot));
      await expectLater(store.toggleFavorite(file), throwsStateError);
      expect(await store.read(file), [9]);
      await expectLater(
        store.remember(EditorKind.word, Uint8List.fromList([1]), 'File.docx'),
        throwsStateError,
      );
      await expectLater(store.setRecent(['f1'], false), throwsStateError);
      expect(await index.readAsString(), '[broken');
    },
  );
}
