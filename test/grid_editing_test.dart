import 'dart:convert';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryGrid implements DocumentBackend {
  bool failEdit = false, failInspect = false;
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic>? last;
  Uint8List encode(Map<String, dynamic> value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
  Map<String, dynamic> decode(Uint8List value) =>
      jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
  @override
  Future<Uint8List> create([String text = '']) async => encode({
    'sheets': [
      {'name': 'Лист 1', 'cells': <String, dynamic>{}},
      {'name': 'Лист 2', 'cells': <String, dynamic>{}},
    ],
  });
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async {
    if (failInspect) {
      failInspect = false;
      throw StateError('inspect failed');
    }
    return last = decode(bytes);
  }

  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async {
    requests.add(Map.of(request));
    if (failEdit) throw StateError('edit failed');
    final data = decode(bytes);
    final cells = data['sheets'][request['sheet']]['cells'] as Map;
    final old = Map<String, dynamic>.from(
      cells[request['address']] as Map? ?? {},
    );
    if (request.containsKey('value')) {
      old['input'] = request['value'];
      old['display'] = request['value'];
    }
    if (request['style'] != null) {
      old['style'] = {...?old['style'] as Map?, ...request['style'] as Map};
    }
    cells[request['address']] = old;
    return encode(data);
  }
}

Future<void> open(WidgetTester tester, MemoryGrid backend) async {
  tester.view.physicalSize = const Size(393, 873);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: OfficeTheme.build(Brightness.light),
      home: NativeGridScreen(
        backend: backend,
        launch: const EditorLaunch(create: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Меню файла'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Сохранить копию'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Formula tools preserve dirty input, call the backend and support undo',
    (tester) async {
      final backend = MemoryGrid();
      await open(tester, backend);
      await tester.tap(find.text('Главная'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Формулы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('∑ Автосумма'));
      await tester.pumpAndSettle();
      expect(backend.requests.single['action'], 'autosum');
      await tester.tap(find.byTooltip('Свернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      await tester.tap(find.byTooltip('Развернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('∑ Автосумма'));
      await tester.pumpAndSettle();
      expect(backend.requests, hasLength(1));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12',
      );
      await tester.tap(find.text('Пересчитать'));
      await tester.pumpAndSettle();
      expect(backend.requests.map((r) => r['action'] ?? 'value'), [
        'autosum',
        'value',
        'recalculate',
      ]);
      expect(backend.requests[1]['value'], '12');
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  const channel = MethodChannel('flutter_file_dialog');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets('Save flushes a dirty XLSX cell without the checkmark', (
    tester,
  ) async {
    final backend = MemoryGrid();
    Uint8List? exported;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          exported = (call.arguments as Map)['data'] as Uint8List;
          return '/test/book.xlsx';
        });
    await open(tester, backend);
    await tester.enterText(find.byType(TextField), '12,5');
    await tester.pump();
    await save(tester);
    expect(
      backend.decode(exported!)['sheets'][0]['cells']['A1']['input'],
      '12,5',
    );
    expect(backend.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'A failed edit prevents stale export and preserves the draft for retry',
    (tester) async {
      final backend = MemoryGrid()..failEdit = true;
      var exports = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            exports++;
            return '/test/book.xlsx';
          });
      await open(tester, backend);
      await tester.enterText(find.byType(TextField), 'Не терять 😀');
      await tester.pump();
      await save(tester);
      expect(exports, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Не терять 😀',
      );
      backend.failEdit = false;
      await save(tester);
      expect(exports, 1);
      expect(
        backend.last!['sheets'][0]['cells']['A1']['input'],
        'Не терять 😀',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Selecting another cell commits the old address; failed changes do not navigate',
    (tester) async {
      final backend = MemoryGrid();
      await open(tester, backend);
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      backend.failEdit = true;
      await tester.tap(find.byKey(const ValueKey('grid-cell-B1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '123',
      );
      backend.failEdit = false;
      await tester.tap(find.byKey(const ValueKey('grid-cell-B1')));
      await tester.pumpAndSettle();
      expect(backend.last!['sheets'][0]['cells']['A1']['input'], '123');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(backend.requests.last['address'], 'A1');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Formatting and a pending value form one change; undo and redo retain the cell',
    (tester) async {
      final backend = MemoryGrid();
      await open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('grid-cell-B1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '42');
      await tester.pump();
      await tester.tap(find.byTooltip('Развернуть инструменты'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Жирный'));
      await tester.pumpAndSettle();
      expect(backend.requests, hasLength(1));
      expect(backend.requests.single['style'], {'bold': true});
      expect(backend.requests.single['value'], '42');
      expect(backend.requests.single['address'], 'B1');
      final painted = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('grid-cell-B1')),
          matching: find.byType(Text),
        ),
      );
      expect(painted.style!.fontWeight, FontWeight.bold);
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(backend.last!['sheets'][0]['cells'], isEmpty);
      backend.failInspect = true;
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Повторить'));
      await tester.pumpAndSettle();
      expect(
        backend.last!['sheets'][0]['cells']['B1']['style']['bold'],
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '42',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Switching sheets commits the original sheet before leaving it', (
    tester,
  ) async {
    final backend = MemoryGrid();
    await open(tester, backend);
    await tester.enterText(find.byType(TextField), '7');
    await tester.pump();
    await tester.tap(find.text('Лист 2'));
    await tester.pumpAndSettle();
    expect(backend.requests.single['sheet'], 0);
    expect(backend.last!['sheets'][0]['cells']['A1']['input'], '7');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField), '8');
    await tester.pump();
    await tester.tap(find.text('Лист 1'));
    await tester.pumpAndSettle();
    expect(backend.requests.last['sheet'], 1);
    expect(backend.last!['sheets'][1]['cells']['A1']['input'], '8');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '7',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo cancels only the current uncommitted input', (
    tester,
  ) async {
    final backend = MemoryGrid();
    await open(tester, backend);
    await tester.enterText(find.byType(TextField), 'Отменить ввод');
    await tester.pump();
    await tester.tap(find.byTooltip('Отменить'));
    await tester.pumpAndSettle();
    expect(backend.requests, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
