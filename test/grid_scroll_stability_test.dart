import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/ui/sheet_viewport.dart';

import 'grid_editing_test.dart' as grid;

class WindowGrid extends grid.MemoryGrid implements GridDocuments {
  int reads = 0, inFlight = 0, maxInFlight = 0;
  Completer<void>? nextRead, nextEdit;
  final states = <Map<String, String>>[{}];
  final editWindows = <GridWindow>[];
  static const style = {
    'fontSize': 12,
    'fontName': 'Test default',
    'align': 'general',
  };
  @override
  Future<Uint8List> create([String text = '']) async => Uint8List.fromList([0]);
  Map<String, dynamic> record(Uint8List bytes, int sheet, int row, int col) {
    final address = '${gridColumnName(col)}${row + 1}';
    final value =
        states[bytes[0]]['$sheet:$address'] ??
        (row == 1 && col == 1 ? '' : 'S$sheet-R${row}C$col');
    return {
      'address': address,
      'input': value,
      'display': value,
      'numeric': false,
      'formula': false,
      'style': style,
    };
  }

  Map<String, dynamic> view(Uint8List bytes, GridWindow w, String selected) {
    final at = gridAddress(selected)!;
    return last = {
      'sheets': [
        for (var sheet = 0; sheet < 2; sheet++)
          {
            'name': 'Лист ${sheet + 1}',
            'cells': sheet == w.sheet
                ? {
                    for (final r in w.requestedRows)
                      for (final c in w.requestedColumns)
                        if (!(r == 1 && c == 1))
                          '${gridColumnName(c)}${r + 1}': record(
                            bytes,
                            sheet,
                            r,
                            c,
                          ),
                  }
                : <String, dynamic>{},
          },
      ],
      'selection': record(bytes, w.sheet, at.row, at.column),
      'defaultCellStyle': style,
      'layout': {
        'defaultRowHeight': 20,
        'defaultColumnWidth': 64,
        'rows': [],
        'columns': [],
        'merges': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> gridView(
    Uint8List bytes,
    GridWindow w,
    String selected,
  ) async {
    reads++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final result = view(bytes, w, selected), gate = nextRead;
    nextRead = null;
    try {
      if (gate != null) await gate.future;
      return result;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) =>
      gridView(bytes, const GridWindow(0, 0, 0), 'A1');
  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async {
    requests.add(Map.of(request));
    final gate = nextEdit;
    nextEdit = null;
    if (gate != null) await gate.future;
    if (failEdit) throw StateError('edit failed');
    states.add({
      ...states[bytes[0]],
      '${request['sheet']}:${request['address']}': request['value'] as String,
    });
    return Uint8List.fromList([states.length - 1]);
  }

  @override
  Future<DocumentSnapshot> editGridView(
    Uint8List bytes,
    Map<String, dynamic> request,
    GridWindow w,
    String selected,
  ) async {
    editWindows.add(w);
    final next = await edit(bytes, request);
    return DocumentSnapshot(next, view(next, w, selected));
  }
}

Finder get formula => find.descendant(
  of: find.byKey(const Key('formula-input')),
  matching: find.byType(TextField),
);
SheetViewportState viewport(WidgetTester tester) =>
    tester.state<SheetViewportState>(find.byType(SheetViewport));
List<Rect> rectangles(WidgetTester tester) => [
  tester.getRect(find.byKey(const Key('grid-formula-bar'))),
  tester.getRect(find.byKey(const Key('grid-sheet-tabs'))),
  tester.getRect(find.byType(EditorToolPanel)),
  tester.getRect(find.byType(SheetViewport)),
];
void main() {
  testWidgets(
    'Loaded populated and empty cell taps do not reload or move lower controls',
    (tester) async {
      final backend = WindowGrid();
      await grid.open(tester, backend);
      final before = rectangles(tester), reads = backend.reads;
      for (final address in ['B2', 'C1', 'D3', 'A1']) {
        await tester.tap(find.byKey(ValueKey('grid-cell-$address')));
        await tester.pump();
        expect(rectangles(tester), before);
        expect(backend.reads, reads);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A pending write and failed edit keep panel and viewport positions stable',
    (tester) async {
      final backend = WindowGrid();
      await grid.open(tester, backend);
      await tester.enterText(formula, 'keep my draft');
      await tester.pump();
      final before = rectangles(tester), gate = Completer<void>();
      backend.nextEdit = gate;
      backend.failEdit = true;
      await tester.tap(find.byKey(const ValueKey('grid-cell-B2')));
      await tester.pump();
      expect(rectangles(tester), before);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(formula).controller!.text,
        'keep my draft',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('grid-formula-bar')),
          matching: find.text('A1'),
        ),
        findsOneWidget,
      );
      expect(rectangles(tester), before);
    },
  );
  testWidgets(
    'Horizontal and vertical return trips paint cached cells before any new read',
    (tester) async {
      final backend = WindowGrid();
      await grid.open(tester, backend);
      final v = viewport(tester);
      final layout = v.widget.layout;
      for (final at in [(200, 30), (0, 30), (200, 0)]) {
        v.goToCell(at.$1, at.$2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pumpAndSettle();
        expect(
          v.widget.layout,
          same(layout),
          reason: 'Read windows retain immutable geometry and its merge index',
        );
        expect(
          find.descendant(
            of: find.byKey(
              ValueKey('grid-cell-${gridColumnName(at.$2)}${at.$1 + 1}'),
            ),
            matching: find.text('S0-R${at.$1}C${at.$2}'),
          ),
          findsOneWidget,
        );
      }
      final reads = backend.reads;
      for (final at in [(0, 0), (200, 30), (0, 30), (200, 0), (0, 0)]) {
        v.goToCell(at.$1, at.$2);
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(
              ValueKey('grid-cell-${gridColumnName(at.$2)}${at.$1 + 1}'),
            ),
            matching: find.text('S0-R${at.$1}C${at.$2}'),
          ),
          findsOneWidget,
        );
        if (at == (0, 0)) {
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('grid-cell-B2')),
              matching: find.text('…'),
            ),
            findsNothing,
          );
        }
        await tester.pump(const Duration(milliseconds: 80));
        expect(backend.reads, reads);
      }
    },
  );
  testWidgets(
    'Continuous movement starts reads before stopping and keeps one viewport read in flight',
    (tester) async {
      final backend = WindowGrid();
      await grid.open(tester, backend);
      final reads = backend.reads, gate = Completer<void>();
      backend.nextRead = gate;
      final v = viewport(tester);
      for (var i = 0; i < 7; i++) {
        v.goToCell(500 + i * 100, 20);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(backend.reads, reads + 1);
      expect(backend.maxInFlight, 1);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(find.text('S0-R1100C20'), findsOneWidget);
      expect(backend.reads, lessThanOrEqualTo(reads + 3));
      expect(backend.maxInFlight, 1);
    },
  );
  testWidgets(
    'A late viewport response does not overwrite a newer selection or its draft',
    (tester) async {
      final backend = WindowGrid();
      await grid.open(tester, backend);
      final gate = Completer<void>();
      backend.nextRead = gate;
      final v = viewport(tester);
      v.goToCell(400, 30);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(backend.inFlight, 1);
      v.goToCell(0, 0);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('grid-cell-B2')));
      await tester.pump();
      await tester.enterText(formula, 'new B2 draft');
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(formula).controller!.text,
        'new B2 draft',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('grid-formula-bar')),
          matching: find.text('B2'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Применить'));
      await tester.pumpAndSettle();
      expect(backend.editWindows.last.contains(0, 0), isTrue);
      expect(find.text('S0-R0C0'), findsOneWidget);
    },
  );
  testWidgets(
    'An old document response cannot restore pre-edit values after cache invalidation',
    (tester) async {
      final backend = WindowGrid();
      await grid.open(tester, backend);
      final gate = Completer<void>();
      backend.nextRead = gate;
      final v = viewport(tester);
      final beforeLayout = v.widget.layout;
      v.goToCell(400, 30);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      v.goToCell(0, 0);
      await tester.pump();
      await tester.enterText(formula, 'updated A1');
      await tester.tap(find.byTooltip('Применить'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        v.widget.layout,
        isNot(same(beforeLayout)),
        reason: 'Edits invalidate geometry before late old reads arrive',
      );
      final cell = find.byKey(const ValueKey('grid-cell-A1'));
      expect(
        find.descendant(of: cell, matching: find.text('updated A1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
