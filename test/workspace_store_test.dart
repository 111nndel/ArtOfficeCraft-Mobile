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
  test(
    'Damaged index is preserved and cannot be silently overwritten',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-index-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final index = File('${directory.path}/index.json');
      await index.writeAsString('[broken');
      final store = WorkspaceStore(directory: directory);
      await store.load();
      expect(store.error, isNotNull);
      await expectLater(
        store.remember(EditorKind.word, Uint8List.fromList([1]), 'File.docx'),
        throwsStateError,
      );
      expect(await index.readAsString(), '[broken');
    },
  );
}
