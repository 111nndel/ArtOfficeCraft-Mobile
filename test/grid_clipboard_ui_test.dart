import 'dart:async';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_clipboard.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show setup;
import 'office_features_test.dart' show tool, press, historyAction;
import 'office_features_backend.dart';
import 'portable_clipboard_test.dart' show MemorySystemClipboard;

class ClipboardBackend extends FeaturesBackend
    implements GridClipboardDocuments {
  ClipboardBackend()
    : super({
        'sheets': [
          {'name': 'Sheet1', 'cells': <String, dynamic>{}},
        ],
      });
  Uint8List? copied;
  bool failPaste = false;
  Completer<void>? copyGate;
  @override
  Future<Map<String, dynamic>> copyGridRange(
    Uint8List bytes,
    Map<String, dynamic> request,
  ) async {
    copied = bytes;
    await copyGate?.future;
    return {
      'range': request['range'],
      'rows': 1,
      'columns': 1,
      'text': decode(bytes)['sheets'][0]['cells']['A1']['input'],
    };
  }

  @override
  Future<DocumentSnapshot> pasteGridRange(
    Uint8List bytes,
    Uint8List source,
    Map<String, dynamic> request,
    GridWindow window,
    String selected,
  ) async {
    final data = decode(bytes);
    data['sheets'][0]['cells'][selected] = decode(
      source,
    )['sheets'][0]['cells']['A1'];
    if (failPaste) throw StateError('Checked preview failed');
    final updated = encode(data);
    return DocumentSnapshot(updated, await inspect(updated));
  }
}

void main() {
  testWidgets('A closed editor cannot overwrite a newer clipboard copy', (tester) async {
    final port = MemorySystemClipboard()..holdFirstWrite = false;
    final clipboard = GridClipboard(port);
    final backend = ClipboardBackend()..copyGate = Completer<void>();
    await setup(tester, const Size(393, 873), 1, NativeGridScreen(
      backend: backend, clipboard: clipboard,
      launch: EditorLaunch(bytes: await backend.create()),
    ));
    final input = find.descendant(
      of: find.byKey(const Key('formula-input')), matching: find.byType(TextField),
    );
    await tester.enterText(input, 'old draft');
    final panel = tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
    panel.sections.expand((s) => s.tools)
        .firstWhere((t) => t.label == 'Копировать').onPressed!();
    for (var i = 0; i < 30 && backend.copied == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(backend.copied, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    final newer = GridClip(Uint8List.fromList([1, 2, 3]), 0, {
      'range': 'A1', 'rows': 1, 'columns': 1, 'text': 'new copy',
    });
    await clipboard.write(newer);
    backend.copyGate!.complete();
    await tester.pumpAndSettle();
    expect(clipboard.current, same(newer));
    expect(port.operations, ['write:new copy']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy flushes draft; paste and failed checked preview preserve one-step history at 320dp',
    (tester) async {
      final port = MemorySystemClipboard()..holdFirstWrite = false;
      final clipboard = GridClipboard(port);
      addTearDown(clipboard.clearLocal);
      final backend = ClipboardBackend();
      await setup(
        tester,
        const Size(320, 800),
        1.6,
        NativeGridScreen(
          clipboard: clipboard,
          backend: backend,
          launch: EditorLaunch(bytes: await backend.create()),
        ),
      );
      final input = find.descendant(
        of: find.byKey(const Key('formula-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'Committed');
      var p = tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
      final copy = p.sections
          .expand((s) => s.tools)
          .firstWhere((t) => t.label == 'Копировать');
      copy.onPressed!();
      await tester.pumpAndSettle();
      expect(
        backend.decode(backend.copied!)['sheets'][0]['cells']['A1']['input'],
        'Committed',
      );
      await tester.tap(find.byKey(const ValueKey('grid-cell-B2')));
      await tester.pumpAndSettle();
      await tool(tester, 'Главная', 'Вставить');
      await press(tester, 'Вставить всё');
      expect(backend.viewed!['sheets'][0]['cells']['B2']['input'], 'Committed');
      await historyAction(tester, true);
      expect(backend.viewed!['sheets'][0]['cells'].containsKey('B2'), false);
      backend.failPaste = true;
      await tool(tester, 'Главная', 'Вставить');
      await press(tester, 'Вставить всё');
      expect(backend.viewed!['sheets'][0]['cells'].containsKey('B2'), false);
      p = tester.widget<EditorToolPanel>(find.byType(EditorToolPanel));
      expect(p.redo, isNotNull);
      await historyAction(tester, false);
      expect(backend.viewed!['sheets'][0]['cells']['B2']['input'], 'Committed');
      expect(tester.takeException(), isNull);
    },
  );
}
