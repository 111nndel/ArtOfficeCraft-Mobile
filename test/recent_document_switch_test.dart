import 'dart:convert';
import 'dart:io';

import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show FakeDocumentBackend;

void main() {
  for (final kind in EditorKind.values) {
    testWidgets(
      '${kind.name}: successful file replacement creates a distinct recent record',
      (tester) async {
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('aoc-editor-switch-'),
        );
        addTearDown(() => directory!.delete(recursive: true));
        final store = WorkspaceStore(directory: directory);
        await tester.runAsync(store.load);
        final session = WorkspaceDocumentSession(store, kind);
        final nativeKind = switch (kind) {
          EditorKind.word => NativeDocumentKind.word,
          EditorKind.excel => NativeDocumentKind.grid,
          EditorKind.slides => NativeDocumentKind.deck,
          EditorKind.pdf => NativeDocumentKind.pdf,
        };
        final backend = FakeDocumentBackend(nativeKind);
        final second = File(
          '${directory!.path}${Platform.pathSeparator}second.${kind.extension}',
        );
        await tester.runAsync(() => second.writeAsBytes(backend.bytes()));
        const files = MethodChannel('flutter_file_dialog');
        const pdf = MethodChannel('artofficecraft/pdf_renderer');
        final calls = <String>[];
        String? pick = second.path;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(files, (call) async => pick);
        final png = Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              pdf,
              (call) async => switch (call.method) {
                'openDocument' => {'session': 1, 'pageCount': 1},
                'renderPage' => png,
                _ => null,
              },
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(files, null);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(pdf, null);
        });
        void changed() {
          calls.add('replace');
          session.startDocument();
        }

        Future<void> remember(Uint8List bytes, String name) async {
          calls.add('remember');
          await session.remember(bytes, name);
        }

        final launch = EditorLaunch(
          bytes: backend.bytes(),
          name: 'first.${kind.extension}',
        );
        final screen = switch (kind) {
          EditorKind.word => NativeWordScreen(
            backend: backend,
            launch: launch,
            onDocumentChanged: changed,
            onRemember: remember,
          ),
          EditorKind.excel => NativeGridScreen(
            backend: backend,
            launch: launch,
            onDocumentChanged: changed,
            onRemember: remember,
          ),
          EditorKind.slides => NativeDeckScreen(
            backend: backend,
            launch: launch,
            onDocumentChanged: changed,
            onRemember: remember,
          ),
          EditorKind.pdf => NativePdfScreen(
            backend: backend,
            renderer: PdfPageRenderer(allowNonAndroidForTesting: true),
            launch: launch,
            onDocumentChanged: changed,
            onRemember: remember,
          ),
        };
        tester.view.physicalSize = const Size(393, 873);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(home: screen));
        Future<void> settleFileIO() async {
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();
        }

        await settleFileIO();
        expect(store.files, hasLength(1));
        expect(calls, ['remember']);
        final firstId = session.id;
        void open() {
          final menu = tester.widget<EditorFileMenu>(
            find.byType(EditorFileMenu),
          );
          menu.commands
              .firstWhere((c) => c.label.startsWith('Открыть'))
              .onPressed!();
        }

        open();
        await settleFileIO();
        expect(calls, ['remember', 'replace', 'remember']);
        expect(session.id, isNot(firstId));
        expect(store.files, hasLength(2));
        pick = null;
        open();
        await settleFileIO();
        expect(calls, [
          'remember',
          'replace',
          'remember',
        ], reason: 'Cancelled picker must retain identity');
        final restored = WorkspaceStore(directory: directory);
        await tester.runAsync(restored.load);
        expect(restored.files.map((f) => f.name).toSet(), {
          'first.${kind.extension}',
          'second.${kind.extension}',
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
