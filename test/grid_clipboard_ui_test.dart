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
  @override
  Future<Map<String, dynamic>> copyGridRange(
    Uint8List bytes,
    Map<String, dynamic> request,
  ) async {
    copied = bytes;
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
  testWidgets(
    'copy flushes draft; paste and failed checked preview preserve one-step history at 320dp',
    (tester) async {
      Map<String, dynamic>? system;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      GridClipboard.clearLocal();
      messenger.setMockMethodCallHandler(GridClipboard.channel, (call) async {
        if (call.method == 'write') {
          system = Map<String, dynamic>.from(call.arguments as Map);
        }
        return call.method == 'read' ? system : null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(GridClipboard.channel, null);
        GridClipboard.clearLocal();
      });
      final backend = ClipboardBackend();
      await setup(
        tester,
        const Size(320, 800),
        1.6,
        NativeGridScreen(
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
