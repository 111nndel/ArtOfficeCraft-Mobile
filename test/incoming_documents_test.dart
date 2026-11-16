import 'dart:async';
import 'dart:io';

import 'package:artofficecraft_mobile/platform/incoming_documents.dart';
import 'package:artofficecraft_mobile/platform/application_storage.dart';
import 'package:artofficecraft_mobile/ui/home_screen.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class IncomingFeed implements IncomingDocuments {
  late Future<void> Function(IncomingDocument) receive;
  @override
  void start(
    Future<void> Function(IncomingDocument) receive,
    void Function(Object) error,
  ) => this.receive = receive;
  @override
  void dispose() {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aoc.incoming.test');
  const codec = StandardMethodCodec();
  Future<void> signal() {
    final done = Completer<void>();
    binding.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(const MethodCall('available')),
      (_) => done.complete(),
    );
    return done.future;
  }

  test(
    'Incoming types use supported MIME/extensions and sanitize display names',
    () {
      for (final kind in EditorKind.values) {
        expect(
          AndroidIncomingDocuments.identify(
            'Report.${kind.extension.toUpperCase()}',
            'application/octet-stream',
          ).$1,
          kind,
        );
        expect(AndroidIncomingDocuments.identify('Report', kind.mimeType), (
          kind,
          'Report.${kind.extension}',
        ));
      }
      expect(
        AndroidIncomingDocuments.identify(
          '../folder/report\u0000.PDF',
          'application/pdf',
        ).$2,
        'report.PDF',
      );
      expect(
        () => AndroidIncomingDocuments.identify('notes.txt', 'text/plain'),
        throwsFormatException,
      );
      expect(
        () =>
            AndroidIncomingDocuments.identify('report.docx', 'application/pdf'),
        throwsFormatException,
      );
    },
  );

  test('Cold and warm events drain in order, repair an empty-read race and release copies', () async {
    final directory = await Directory.systemTemp.createTemp('aoc-incoming-');
    addTearDown(() => directory.delete(recursive: true));
    final queue = <Map<String, Object>>[];
    Future<Map<String, Object>> file(String name) async {
      final f = File('${directory.path}/$name');
      await f.writeAsBytes([1, 2, 3]);
      return {'path': f.path, 'name': name, 'mime': 'application/pdf'};
    }

    queue.add(await file('cold.pdf'));
    final warm = await file('warm.pdf');
    var injected = false;
    final received = <String>[], released = <String>[];
    final done = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'release') {
        final path = (call.arguments as Map)['path'] as String;
        await File(path).delete();
        released.add(path);
        if (released.length == 2) done.complete();
        return null;
      }
      if (queue.isNotEmpty) return queue.removeAt(0);
      if (!injected) {
        injected = true;
        queue.add(warm);
        await signal();
      }
      return null;
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final source = AndroidIncomingDocuments(channel: channel);
    addTearDown(source.dispose);
    source.start((document) async {
      received.add(document.name);
      expect(document.bytes, [1, 2, 3]);
    }, (error) => fail('$error'));
    await done.future.timeout(const Duration(seconds: 5));
    expect(received, ['cold.pdf', 'warm.pdf']);
    expect(await directory.list().isEmpty, isTrue);
  });

  test('Unsupported or empty input is released and a following document still opens', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aoc-incoming-invalid-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final queue = <Map<String, String>>[];
    for (final name in ['bad.txt', 'empty.pdf', 'good.pdf']) {
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(name == 'empty.pdf' ? [] : [1]);
      queue.add({'path': file.path, 'name': name});
    }
    var errors = 0, releases = 0;
    final received = <String>[], done = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'take') {
        return queue.isEmpty ? null : queue.removeAt(0);
      }
      await File((call.arguments as Map)['path'] as String).delete();
      if (++releases == 3) done.complete();
      return null;
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final source = AndroidIncomingDocuments(channel: channel);
    addTearDown(source.dispose);
    source.start((d) async => received.add(d.name), (_) => errors++);
    await done.future.timeout(const Duration(seconds: 5));
    expect(errors, 2);
    expect(received, ['good.pdf']);
    expect(await directory.list().isEmpty, isTrue);
  });

  testWidgets('A warm external open preserves the previous editor on Back', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'aoc-incoming-home-',
      );
      final storage = DirectoryApplicationStorage(directory);
      final workspace = WorkspaceStore(storage: storage);
      final drafts = DraftStore(storage: storage);
      await workspace.load();
      await drafts.load();
      return (directory, workspace, drafts);
    }))!;
    final (directory, workspace, drafts) = fixture;
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(workspace.dispose);
    addTearDown(drafts.dispose);
    final incoming = IncomingFeed();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          toggleTheme: () {},
          theme: ThemeMode.light,
          incoming: incoming,
          workspace: workspace,
          drafts: drafts,
          storage: DirectoryApplicationStorage(directory),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => incoming.receive(
        IncomingDocument(
          EditorKind.word,
          'First.docx',
          Uint8List.fromList([1]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.state(find.byType(NativeWordScreen));
    await tester.runAsync(
      () => incoming.receive(
        IncomingDocument(
          EditorKind.excel,
          'Second.xlsx',
          Uint8List.fromList([2]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NativeGridScreen>(find.byType(NativeGridScreen))
          .launch!
          .name,
      'Second.xlsx',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(NativeWordScreen)), same(first));
    expect(
      tester
          .widget<NativeWordScreen>(find.byType(NativeWordScreen))
          .launch!
          .name,
      'First.docx',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
