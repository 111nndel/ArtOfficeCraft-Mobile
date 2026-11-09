import 'package:artofficecraft_mobile/platform/document_files.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/ui/home_screen.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/native/native_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show FakeDocumentBackend, setup;

void main() {
  const channel = MethodChannel('flutter_file_dialog');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  for (final kind in EditorKind.values) {
    testWidgets(
      'Home and ${kind.name} editor restrict the real picker request',
      (tester) async {
        final requests = <Map>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'pickFile') {
                requests.add(call.arguments as Map);
              }
              return null; // User cancels: the current screen/document must remain.
            });
        tester.view.physicalSize = const Size(393, 873);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final workspace = WorkspaceStore()..loaded = true;
        final drafts = DraftStore()..loaded = true;
        addTearDown(workspace.dispose);
        addTearDown(drafts.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              toggleTheme: () {},
              theme: ThemeMode.light,
              workspace: workspace,
              drafts: drafts,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Открыть файл с устройства'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Открыть файл с устройства')),
          alignment: .4,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Открыть файл с устройства'));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.widgetWithText(ListTile, kind.label),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        expect(find.byType(HomeScreen), findsOneWidget);
        final backend = FakeDocumentBackend(switch (kind) {
          EditorKind.word => NativeDocumentKind.word,
          EditorKind.excel => NativeDocumentKind.grid,
          EditorKind.slides => NativeDocumentKind.deck,
          EditorKind.pdf => NativeDocumentKind.pdf,
        });
        final screen = switch (kind) {
          EditorKind.word => NativeWordScreen(backend: backend),
          EditorKind.excel => NativeGridScreen(backend: backend),
          EditorKind.slides => NativeDeckScreen(backend: backend),
          EditorKind.pdf => NativePdfScreen(backend: backend),
        };
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Открыть ${kind.format}'));
        await tester.pumpAndSettle();
        expect(requests, hasLength(2));
        for (final request in requests) {
          expect(request['mimeTypesFilter'], [kind.mimeType]);
          expect(request['fileExtensionsFilter'], [kind.extension]);
          expect(request['copyFileToCacheDir'], isTrue);
          expect(request['mimeTypesFilter'], isNot(contains('*/*')));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final kind in EditorKind.values) {
    testWidgets('${kind.name} exports through an injected file service', (tester) async {
      final files = RecordingDocumentFiles();
      final backend = FakeDocumentBackend(switch (kind) {
        EditorKind.word => NativeDocumentKind.word,
        EditorKind.excel => NativeDocumentKind.grid,
        EditorKind.slides => NativeDocumentKind.deck,
        EditorKind.pdf => NativeDocumentKind.pdf,
      });
      const launch = EditorLaunch(create: true);
      final screen = switch (kind) {
        EditorKind.word => NativeWordScreen(backend: backend, files: files, launch: launch),
        EditorKind.excel => NativeGridScreen(backend: backend, files: files, launch: launch),
        EditorKind.slides => NativeDeckScreen(backend: backend, files: files, launch: launch),
        EditorKind.pdf => NativePdfScreen(backend: backend, files: files, launch: launch),
      };
      await setup(tester, const Size(393, 873), 1, screen);
      await tester.tap(find.byTooltip('Меню файла'));
      await tester.pumpAndSettle();
      final saveLabel = switch (kind) {
        EditorKind.word => 'Сохранить как DOCX',
        EditorKind.excel => 'Сохранить копию',
        EditorKind.slides => 'Сохранить копию PPTX',
        EditorKind.pdf => 'Сохранить PDF',
      };
      await tester.tap(find.text(saveLabel));
      await tester.pumpAndSettle();
      expect(files.kind, kind);
      expect(files.bytes, isNotEmpty);
      expect(files.name, endsWith('.${kind.extension}'));
      expect(tester.takeException(), isNull);
    });
  }
}

class RecordingDocumentFiles implements DocumentFiles {
  EditorKind? kind;
  Uint8List? bytes;
  String? name;

  @override
  Future<String?> open(EditorKind kind) async => null;

  @override
  Future<String?> save({required EditorKind kind, required Uint8List bytes, required String name}) async {
    this.kind = kind;
    this.bytes = bytes;
    this.name = name;
    return null; // Cancellation still uses the editor's existing save guard.
  }
}
