import 'grid_layout.dart';
import '../workspace/document_picker.dart';
import '../workspace/editor_kind.dart';
import '../l10n/app_strings.dart';
import '../ui/sheet_viewport.dart';
import '../ui/grid_cells_painter.dart';
import '../workspace/draft_store.dart';

import 'dart:async';

import 'document_history.dart';
import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import 'document_backend.dart';
import 'grid_window.dart';
import 'grid_selection.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';

class NativeGridScreen extends StatefulWidget {
  const NativeGridScreen({
    super.key,
    this.launch,
    this.onRemember,
    this.onDocumentChanged,
    this.draft,
    this.backend,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  final VoidCallback? onDocumentChanged;
  final DraftSession? draft;
  final DocumentBackend? backend;
  @override
  State<NativeGridScreen> createState() => _NativeGridScreenState();
}

class _NativeGridScreenState extends State<NativeGridScreen> {
  bool restoringDraft = false, draftQueued = false;
  void draftStatusChanged() {
    if (mounted) setState(() {});
  }

  void queueDraft() {
    if (draftQueued || restoringDraft || widget.draft == null) return;
    draftQueued = true;
    scheduleMicrotask(() {
      draftQueued = false;
      final bytes = book;
      if (!mounted || restoringDraft || bytes == null) return;
      widget.draft!.update(
        bytes: bytes,
        name: filename,
        dirty: modified || inputDirty,
        editor: {
          'modified': modified,
          'sheet': sheetIndex,
          'selected': selected,
          'input': input.text,
        },
      );
    });
  }

  final toolPanel = GlobalKey<EditorToolPanelState>();
  bool toolsExpanded = false;
  bool headingsPinned = false;
  bool formulaExpanded = false;
  late final DocumentBackend? bridge =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.grid);
  Uint8List? book;
  String filename = 'Книга.xlsx', selected = 'A1';
  int sheetIndex = 0;
  bool modified = false, busy = false;
  final input = TextEditingController();
  final history = DocumentHistory();
  final addressInput = TextEditingController();
  Map<String, dynamic> selectedCell = {};
  GridLayout layout = GridLayout.fromJson(null);
  GridWindow loadedWindow = const GridWindow(0, 0, 0);
  GridWindow? wantedWindow;
  Timer? viewTimer;
  bool loadingView = false, viewFailed = false;
  bool get inputDirty => input.text != currentInput;
  Map<String, dynamic> get cellStyle =>
      Map<String, dynamic>.from(selectedCell['style'] as Map? ?? {});
  List<Map<String, dynamic>> sheets = [];
  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
    inputFocus.dispose();
    newSheetName.dispose();
    rangeInput.dispose();
    viewTimer?.cancel();
    addressInput.dispose();
    input.dispose();
    if (widget.backend == null) unawaited(closeDocumentBackend(bridge));
    super.dispose();
  }

  Map<String, dynamic> _sheetCells = {};
  Map<String, dynamic> get cells => _sheetCells;
  void refreshCells() {
    _sheetCells = sheets.isEmpty
        ? {}
        : Map<String, dynamic>.from(sheets[sheetIndex]['cells'] as Map);
  }

  String get currentInput {
    return selectedCell['input']?.toString() ?? '';
  }

  void tip(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: UiText(msg), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy || bridge == null) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      tip('Ошибка: $e');
    } finally {
      if (mounted) setState(() => busy = false);
      queueDraft();
      scheduleView();
    }
  }

  Future<void> setBook(
    Uint8List data, {
    String? name,
    bool edited = false,
    int? index,
  }) async {
    data = immutableDocumentBytes(data);
    var window = GridWindow(index ?? 0, 0, 0);
    var parsed = await bridge!.inspectGrid(data, window, 'A1');
    final active = index ?? (parsed['activeSheet'] as int? ?? 0);
    if (active != window.sheet) {
      window = GridWindow(active, 0, 0);
      parsed = await bridge!.inspectGrid(data, window, 'A1');
    }
    if (!mounted) return;
    final list = parsed['sheets'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('Листы не найдены');
    }
    setState(() {
      book = data;
      rangeSelection = null;
      rangeInput.clear();
      sheets = list.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      sheetIndex = window.sheet.clamp(0, sheets.length - 1);
      selected = 'A1';
      acceptView(parsed, window);
      wantedWindow = window;
      input.text = currentInput;
      if (name != null) filename = name;
      modified = edited;
      history.clear();
    });
    gridViewport.currentState?.reset();
  }

  Future<bool> askDiscard() async {
    if (!modified && !inputDirty) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const UiText('Изменения не сохранены'),
        content: const UiText('Открыть другую книгу без сохранения этой?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const UiText('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const UiText('Продолжить'),
          ),
        ],
      ),
    );
    return choice == true;
  }

  Future<void> create() => run(() async {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    String translated(String value) => strings?.translate(value) ?? value;
    if (!await askDiscard()) return;
    var bytes = await bridge!.create();
    if (widget.launch?.template == true) {
      const values = {
        'A1': 'Статья',
        'B1': 'План',
        'C1': 'Факт',
        'D1': 'Разница',
        'A2': 'Дизайн',
        'B2': '85000',
        'C2': '78000',
        'D2': '=B2-C2',
        'A3': 'Разработка',
        'B3': '160000',
        'C3': '142000',
        'D3': '=B3-C3',
        'A5': 'Итого',
        'B5': '=SUM(B2:B3)',
        'C5': '=SUM(C2:C3)',
        'D5': '=SUM(D2:D3)',
      };
      for (final entry in values.entries) {
        bytes = await bridge!.edit(bytes, {
          'sheet': 0,
          'address': entry.key,
          'value': translated(entry.value),
        });
      }
    }
    await setBook(
      bytes,
      name: widget.launch?.template == true
          ? translated('Бюджет команды.xlsx')
          : translated('Новая книга.xlsx'),
      edited: true,
    );
    widget.onDocumentChanged?.call();
  });
  Future<void> open() => run(() async {
    if (!await askDiscard()) return;
    final path = await pickDocument(EditorKind.excel);
    if (path == null) return;
    final file = File(path);
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Размер файла более 64 МБ');
    }
    final name = importedFilename(path, 'xlsx');
    await setBook(await file.readAsBytes(), name: name);
    widget.onDocumentChanged?.call();
    await rememberCurrent();
    tip('XLSX прочитан GridCraft');
  });
  Future<void> save() => run(() async {
    if (restoringDraft) {
      throw const FormatException(
        'Черновик восстановлен не полностью. Он сохранён на главном экране.',
      );
    }
    if (book == null) return;
    await flushInput();
    final name =
        '${filename.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '')}-ArtOfficeCraft.xlsx';
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: book!,
        fileName: name,
        mimeTypesFilter: const [
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ],
      ),
    );
    if (path == null) return;
    setState(() => modified = false);
    await rememberCurrent();
    tip('Сохранена новая копия XLSX');
  });
  List<Map<String, dynamic>> parsedSheets(Map<String, dynamic> parsed) {
    final list = parsed['sheets'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('Листы не найдены');
    }
    return list.map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  void acceptView(Map<String, dynamic> parsed, GridWindow window) {
    sheets = parsedSheets(parsed);
    refreshCells();
    selectedCell = Map<String, dynamic>.from(parsed['selection'] as Map? ?? {});
    layout = GridLayout.fromJson(parsed['layout'] as Map?);
    selected = selectedCell['address'] as String? ?? selected;
    loadedWindow = window;
    viewFailed = false;
  }

  void visibleWindow(GridWindow region) {
    final visible = region.rowIndices != null
        ? GridWindow.visible(
            sheetIndex,
            region.rowIndices!,
            region.columnIndices!,
          )
        : GridWindow(
            sheetIndex,
            region.row,
            region.column,
            rows: region.rows,
            columns: region.columns,
          );
    if (loadedWindow.covers(visible)) {
      wantedWindow = loadedWindow;
      viewTimer?.cancel();
      if (viewFailed) setState(() => viewFailed = false);
      return;
    }
    wantedWindow = visible.buffered;
    viewFailed = false;
    scheduleView();
  }

  void scheduleView() {
    viewTimer?.cancel();
    final wanted = wantedWindow;
    if (!mounted ||
        busy ||
        loadingView ||
        viewFailed ||
        book == null ||
        wanted == null ||
        loadedWindow.covers(wanted)) {
      return;
    }
    viewTimer = Timer(const Duration(milliseconds: 160), loadVisibleWindow);
  }

  Future<void> loadVisibleWindow() async {
    final bytes = book;
    final window = wantedWindow;
    final address = selected;
    if (!mounted ||
        busy ||
        loadingView ||
        bytes == null ||
        window == null ||
        loadedWindow.covers(window)) {
      return;
    }
    setState(() => loadingView = true);
    try {
      final parsed = await bridge!.inspectGrid(bytes, window, address);
      if (mounted &&
          !busy &&
          identical(bytes, book) &&
          address == selected &&
          window.sheet == sheetIndex) {
        setState(() => acceptView(parsed, window));
      }
    } catch (_) {
      if (mounted && identical(bytes, book) && window.sheet == sheetIndex) {
        setState(() => viewFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => loadingView = false);
        scheduleView();
      }
    }
  }

  void install(
    Uint8List bytes,
    Map<String, dynamic> parsed,
    GridWindow window,
  ) {
    setState(() {
      book = bytes;
      if (sheetIndex != window.sheet) {
        rangeSelection = null;
        rangeInput.clear();
      }
      sheetIndex = window.sheet;
      wantedWindow = window;
      acceptView(parsed, window);
      input.text = currentInput;
      modified = true;
    });
  }

  Future<void> applyEdit(Map<String, dynamic> request) async {
    final previous = book!;
    final window = loadedWindow;
    final updated = await bridge!.editAndInspectGrid(
      previous,
      request,
      window,
      selected,
    );
    parsedSheets(updated.preview);
    if (!mounted) return;
    history.push(previous, position: sheetIndex);
    install(updated.bytes, updated.preview, window);
    await rememberCurrent();
  }

  Future<void> flushInput() async {
    if (book == null || !inputDirty) return;
    await applyEdit({
      'sheet': sheetIndex,
      'address': selected,
      'value': input.text,
    });
  }

  Future<void> commit() => run(() async {
    await flushInput();
    inputFocus.unfocus();
  });
  Future<void> autoSum() => run(() async {
    if (book == null) return;
    if (input.text.isNotEmpty || currentInput.isNotEmpty) {
      tip('Выберите пустую ячейку под числами или справа от них');
      return;
    }
    await applyEdit({
      'action': 'autosum',
      'sheet': sheetIndex,
      'address': selected,
    });
    inputFocus.unfocus();
  });
  Future<void> recalculate() => run(() async {
    if (book == null) return;
    await flushInput();
    await applyEdit({
      'action': 'recalculate',
      'sheet': sheetIndex,
      'address': selected,
    });
    inputFocus.unfocus();
    tip('Формулы пересчитаны');
  });
  Future<void> selectCell(
    String address, {
    bool reveal = false,
    bool keepRange = false,
  }) => run(() async {
    if (address == selected && !reveal) {
      if (!keepRange) {
        setState(() {
          rangeSelection = null;
          rangeInput.clear();
        });
      }
      return;
    }
    await flushInput();
    final position = gridAddress(address);
    if (position == null) {
      throw const FormatException('Введите адрес от A1 до XFD1048576');
    }
    final window = loadedWindow.contains(position.row, position.column)
        ? loadedWindow
        : GridWindow(
            sheetIndex,
            position.row,
            position.column,
            rows: 1,
            columns: 1,
          ).buffered;
    final parsed = await bridge!.inspectGrid(book!, window, address);
    if (!mounted) return;
    setState(() {
      selected = address;
      if (!keepRange) {
        rangeSelection = null;
        rangeInput.clear();
      }
      acceptView(parsed, window);
      input.text = currentInput;
    });
    if (reveal) {
      gridViewport.currentState?.goToCell(position.row, position.column);
    }
    if (reveal) FocusManager.instance.primaryFocus?.unfocus();
  });
  Future<void> chooseSheet(int idx) => run(() async {
    if (idx == sheetIndex) return;
    await flushInput();
    final window = GridWindow(idx, 0, 0);
    final parsed = await bridge!.inspectGrid(book!, window, 'A1');
    if (!mounted) return;
    setState(() {
      sheetIndex = idx;
      rangeSelection = null;
      rangeInput.clear();
      selected = 'A1';
      acceptView(parsed, window);
      wantedWindow = window;
      input.text = currentInput;
    });
    gridViewport.currentState?.reset();
  });
  Future<void> formatCell(Map<String, dynamic> style) => run(() async {
    if (book == null) return;
    if (rangeSelection != null) {
      await flushInput();
      await applyEdit({
        'action': 'format_range',
        'sheet': sheetIndex,
        'address': selected,
        'range': rangeSelection!.address,
        'style': style,
      });
      return;
    }
    await applyEdit({
      'action': 'format',
      'sheet': sheetIndex,
      'address': selected,
      if (inputDirty) 'value': input.text,
      'style': style,
    });
  });
  Future<void> restore(bool undo) => run(() async {
    if (book == null) return;
    if (inputDirty) {
      if (undo) setState(() => input.text = currentInput);
      return;
    }
    final target = undo ? history.undoTarget : history.redoTarget;
    if (target == null) return;
    final targetSheet =
        (undo ? history.undoPosition : history.redoPosition) ?? sheetIndex;
    final differentSheet = targetSheet != sheetIndex;
    final window = differentSheet
        ? GridWindow(targetSheet, 0, 0)
        : loadedWindow;
    final parsed = await bridge!.inspectGrid(
      target,
      window,
      differentSheet ? 'A1' : selected,
    );
    parsedSheets(parsed);
    if (!mounted) return;
    if (undo) {
      history.undo(book!, position: sheetIndex);
    } else {
      history.redo(book!, position: sheetIndex);
    }
    viewTimer?.cancel();
    install(target, parsed, window);
    if (differentSheet) gridViewport.currentState?.reset();
    await rememberCurrent();
  });

  GridSelection? rangeSelection;
  final rangeInput = TextEditingController();
  bool updateRange(GridSelection value, {bool message = true}) {
    final expanded = value.includingMerges(layout);
    if (expanded.cellCount > GridSelection.maxCells) {
      if (message) tip('Выберите не более 4096 ячеек за одну операцию');
      return false;
    }
    setState(() {
      rangeSelection = expanded;
      rangeInput.text = expanded.address;
    });
    return true;
  }

  Future<void> beginRange(String address) async {
    await selectCell(address);
    if (!mounted || busy || selected != address) return;
    inputFocus.unfocus();
    final p = gridAddress(selected)!;
    updateRange(GridSelection(p.row, p.column, p.row, p.column));
  }

  Future<void> focusRange() async {
    final value = rangeSelection;
    if (value == null || busy) return;
    await selectCell(
      '${gridColumnName(value.column)}${value.row + 1}',
      keepRange: true,
    );
  }

  Future<void> chooseRange() async {
    final parsed = GridSelection.parse(rangeInput.text);
    if (parsed == null) {
      tip('Введите диапазон, например A1:D10');
      return;
    }
    final value = parsed.includingMerges(layout);
    if (value.cellCount > GridSelection.maxCells) {
      tip('Выберите не более 4096 ячеек за одну операцию');
      return;
    }
    final address = '${gridColumnName(value.column)}${value.row + 1}';
    await selectCell(address);
    if (!mounted || busy || selected != address) return;
    updateRange(value);
    inputFocus.unfocus();
    gridViewport.currentState?.goToCell(value.row, value.column);
  }

  Future<void> clearSelected() => run(() async {
    if (book == null) return;
    await flushInput();
    final p = gridAddress(selected)!;
    final range =
        rangeSelection ??
        GridSelection(p.row, p.column, p.row, p.column).includingMerges(layout);
    await applyEdit({
      'action': 'clear_range',
      'sheet': sheetIndex,
      'address': selected,
      'range': range.address,
    });
    inputFocus.unfocus();
  });

  final newSheetName = TextEditingController();
  Future<void> addSheet() => run(() async {
    if (book == null) return;
    await flushInput();
    final previous = book!, previousSheet = sheetIndex;
    final window = GridWindow(sheets.length, 0, 0);
    final name = newSheetName.text.trim();
    final update = await bridge!.editAndInspectGrid(
      previous,
      {
        'action': 'add_sheet',
        'sheet': sheetIndex,
        'address': selected,
        if (name.isNotEmpty) 'name': name,
      },
      window,
      'A1',
    );
    parsedSheets(update.preview);
    if (!mounted) return;
    history.push(previous, position: previousSheet);
    viewTimer?.cancel();
    install(update.bytes, update.preview, window);
    gridViewport.currentState?.reset();
    newSheetName.clear();
    await rememberCurrent();
    tip('Лист создан');
  });
  final inputFocus = FocusNode();
  Widget header(String text) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: const Border(
        right: BorderSide(color: Color(0xffe5e9ef)),
        bottom: BorderSide(color: Color(0xffe5e9ef)),
      ),
    ),
    child: Text(
      text,
      maxLines: 1,
      textScaler: TextScaler.noScaling,
      overflow: TextOverflow.clip,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
        height: 1,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
  Widget cell(String address) {
    final item = address == selected ? selectedCell : cells[address];
    final position = gridAddress(address)!;
    final known =
        item is Map || loadedWindow.contains(position.row, position.column);
    final value = !known
        ? '…'
        : item is Map
        ? item['display']?.toString() ?? ''
        : '';
    final style = Map<String, dynamic>.from(
      item is Map ? item['style'] as Map? ?? {} : {},
    );
    final numeric = item is Map && item['numeric'] == true;
    final fill = rgb(style['fill']) ?? Colors.white;
    final text = Text(
      value,
      softWrap: style['wrap'] == true,
      textAlign: switch (style['align']) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => numeric ? TextAlign.right : TextAlign.left,
      },
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        height: 1.1,
        color: rgb(style['color']) ?? const Color(0xff172634),
        fontSize: ((style['fontSize'] as num?)?.toDouble() ?? 12) * 4 / 3,
        fontFamily: style['fontName'] as String?,
        fontWeight: style['bold'] == true ? FontWeight.bold : FontWeight.normal,
        fontStyle: style['italic'] == true
            ? FontStyle.italic
            : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (style['underline'] == true) TextDecoration.underline,
          if (style['strike'] == true) TextDecoration.lineThrough,
        ]),
      ),
      maxLines: style['wrap'] == true ? null : 1,
      overflow: TextOverflow.clip,
    );
    return InkWell(
      key: ValueKey('grid-cell-$address'),
      onTap: busy ? null : () => selectCell(address),
      onLongPress: busy ? null : () => beginRange(address),
      child: Container(
        alignment: Alignment(
          switch (style['align']) {
            'left' => -1.0,
            'center' => 0.0,
            'right' => 1.0,
            _ => numeric ? 1.0 : -1.0,
          },
          switch (style['verticalAlign']) {
            'top' => -1.0,
            'bottom' => 1.0,
            _ => 0.0,
          },
        ),
        padding: EdgeInsets.only(
          left: 3 + ((style['indent'] as num?)?.toDouble() ?? 0) * 8,
          right: 3,
        ),
        decoration: BoxDecoration(
          color: address == selected
              ? Color.alphaBlend(const Color(0x16188458), fill)
              : fill,
          border: address == selected
              ? Border.all(color: const Color(0xff188458), width: 2)
              : Border(
                  left: cellBorder(style, 'left'),
                  right: cellBorder(style, 'right'),
                  top: cellBorder(style, 'top'),
                  bottom: cellBorder(style, 'bottom'),
                ),
        ),
        child: ClipRect(
          child: style['shrink'] == true && style['wrap'] != true
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment(switch (style['align']) {
                    'center' => 0.0,
                    'right' => 1.0,
                    _ => numeric ? 1.0 : -1.0,
                  }, 0),
                  child: text,
                )
              : text,
        ),
      ),
    );
  }

  static Color? rgb(dynamic value) {
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
  }

  BorderSide cellBorder(Map<String, dynamic> style, String side) {
    final border = (style['borders'] as Map?)?[side] as Map?;
    final width = (border?['width'] as num?)?.toDouble() ?? 0;
    return BorderSide(
      color: width > 0
          ? rgb(border?['color']) ?? Colors.black
          : layout.showGridlines
          ? const Color(0xffe5e9ef)
          : Colors.transparent,
      width: width > 0 ? width.clamp(.3, 6).toDouble() : .7,
    );
  }

  final gridViewport = GlobalKey<SheetViewportState>();
  Widget grid() => Stack(
    children: [
      SheetViewport.cells(
        key: gridViewport,
        rowCount: gridMaxRows,
        columnCount: gridMaxColumns,
        rowHeaderExtent: 46,
        columnHeaderExtent: 28,
        layout: layout,
        selection: rangeSelection,
        onSelectionChanged: busy
            ? null
            : (value) => updateRange(value, message: false),
        onSelectionEnd: busy ? null : focusRange,
        freezeHeadings: headingsPinned,
        compactCellsBuilder: (_, rect, rows, columns) => RepaintBoundary(
          child: CustomPaint(
            key: const Key('grid-cells-canvas'),
            painter: GridCellsPainter(
              GridLayout(
                rows,
                columns,
                layout.merges,
                showGridlines: layout.showGridlines,
              ),
              cells,
              selected,
              viewport: rect,
              scale: gridViewport.currentState?.zoom ?? 1,
            ),
          ),
        ),
        onCellTap: (row, col) => selectCell('${gridColumnName(col)}${row + 1}'),
        onCellLongPress: (row, col) =>
            beginRange('${gridColumnName(col)}${row + 1}'),
        onResize: busy ? null : resizeLine,
        corner: header(''),
        columnHeaderBuilder: (context, col) => header(gridColumnName(col)),
        rowHeaderBuilder: (context, row) => header('${row + 1}'),
        cellBuilder: (context, row, col) =>
            cell('${gridColumnName(col)}${row + 1}'),
        onWindowChanged: visibleWindow,
      ),
      if (loadingView)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(),
        ),
      if (viewFailed)
        Positioned(
          top: 28,
          left: 4,
          right: 4,
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: TextButton.icon(
              onPressed: () {
                setState(() => viewFailed = false);
                scheduleView();
              },
              icon: const Icon(Icons.refresh),
              label: const UiText('Повторить загрузку области'),
            ),
          ),
        ),
    ],
  );

  Future<void> resizeLine(bool row, int index, double size) => run(() async {
    if (book == null) return;
    await flushInput();
    await applyEdit({
      'action': row ? 'rowHeight' : 'columnWidth',
      'sheet': sheetIndex,
      'address': selected,
      'index': index,
      'size': size,
    });
  });

  void goToAddress() {
    final position = gridAddress(addressInput.text);
    if (position == null) {
      tip('Введите адрес от A1 до XFD1048576');
      return;
    }
    unawaited(
      selectCell(
        '${gridColumnName(position.column)}${position.row + 1}',
        reveal: true,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    restoringDraft = widget.launch?.recovery != null;
    widget.draft?.addListener(draftStatusChanged);
    input.addListener(() {
      if (mounted) setState(() {});
      queueDraft();
    });
    inputFocus.addListener(() {
      if (mounted) setState(() {});
      queueDraft();
    });
    final request = widget.launch;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (request.bytes != null) {
          run(() async {
            await setBook(request.bytes!, name: request.name);
            await restoreDraft(request.recovery);
            if (request.recovery == null) await rememberCurrent();
          });
        } else if (request.create) {
          create();
        }
      });
    }
  }

  Future<void> restoreDraft(Map<String, dynamic>? state) async {
    if (state == null) return;
    final sheet = state['sheet'] as int;
    final address = state['selected'] as String;
    if (sheet < 0 || sheet >= sheets.length || gridAddress(address) == null) {
      throw const FormatException(
        'Не удалось восстановить выбранную ячейку. Черновик сохранён.',
      );
    }
    final position = gridAddress(address)!;
    final window = GridWindow(
      sheet,
      position.row,
      position.column,
      rows: 1,
      columns: 1,
    ).buffered;
    final parsed = await bridge!.inspectGrid(book!, window, address);
    if (!mounted) return;
    sheetIndex = sheet;
    selected = address;
    acceptView(parsed, window);
    wantedWindow = window;
    input.text = state['input'] as String;
    modified = state['modified'] == true;
    restoringDraft = false;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        gridViewport.currentState?.goToCell(position.row, position.column);
      }
    });
    queueDraft();
  }

  Future<void> rememberCurrent() async {
    final bytes = book;
    if (bytes == null || widget.onRemember == null) return;
    try {
      await widget.onRemember!(bytes, filename);
    } catch (_) {
      tip(
        'Рабочая копия не добавлена в историю. Файл можно сохранить через «Сохранить копию».',
      );
    }
  }

  Widget editorPanel() {
    EditorTool action(
      String label,
      IconData icon,
      Map<String, dynamic> patch,
    ) => EditorTool(
      label,
      icon,
      onPressed: busy ? null : () => formatCell(patch),
    );
    EditorTool colors(String title, String property, IconData icon) =>
        EditorTool(
          title,
          icon,
          children: [
            action(
              property == 'fill' ? 'Без заливки' : 'Автоматический',
              icon,
              {property: null},
            ),
            for (final color in [
              ('Чёрный', '#202938'),
              ('Белый', '#FFFFFF'),
              ('Синий', '#3565CA'),
              ('Зелёный', '#147553'),
              ('Красный', '#C64246'),
              ('Жёлтый', '#FFF2CC'),
              ('Светло-зелёный', '#E2F0D9'),
            ])
              action(color.$1, icon, {property: color.$2}),
          ],
        );
    final zoomTool = EditorTool(
      'Масштаб',
      Icons.zoom_in,
      children: [
        for (final percent in [
          10,
          15,
          25,
          33,
          50,
          75,
          100,
          125,
          150,
          200,
          300,
          400,
          500,
        ])
          EditorTool(
            '$percent%',
            Icons.zoom_in,
            onPressed: () => gridViewport.currentState?.setZoom(percent / 100),
          ),
      ],
    );
    return EditorToolPanel(
      key: toolPanel,
      color: const Color(0xff17815c),
      onExpandedChanged: (value) => setState(() => toolsExpanded = value),
      undo: !busy && (inputDirty || history.canUndo)
          ? () => restore(true)
          : null,
      redo: !busy && !inputDirty && history.canRedo
          ? () => restore(false)
          : null,
      sections: officeSections(
        'grid',
        exclude: {'Ж', 'Масштаб'},
        leading: {
          'Формулы': [
            EditorTool(
              'Автосумма складывает соседние числа сверху, а если их нет — слева. Выберите пустую ячейку для результата.',
              Icons.info_outline,
              inline: true,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(12),
                child: UiText(
                  'Автосумма складывает соседние числа сверху, а если их нет — слева. Выберите пустую ячейку для результата.',
                ),
              ),
            ),
          ],
          'Вид': [
            zoomTool,
            EditorTool(
              headingsPinned ? 'Открепить заголовки' : 'Закрепить заголовки',
              Icons.push_pin_outlined,
              onPressed: () => setState(() => headingsPinned = !headingsPinned),
            ),
            EditorTool(
              'Перейти к ячейке',
              Icons.my_location,
              builder: (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('grid-address-input'),
                    controller: addressInput,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Адрес ячейки'),
                      hintText: 'AA1000',
                    ),
                    onSubmitted: (_) => goToAddress(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : goToAddress,
                    child: const UiText('Перейти'),
                  ),
                ],
              ),
            ),
            EditorTool(
              'Размер строк и столбцов',
              Icons.touch_app_outlined,
              inline: true,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(12),
                child: UiText(
                  'Удерживайте заголовок строки или столбца и тяните для изменения размера. Двумя пальцами изменяйте масштаб таблицы.',
                ),
              ),
            ),
          ],
          'Главная': [
            EditorTool(
              'Стиль',
              Icons.text_fields,
              inline: true,
              builder: (_) => EditorTextStyleControls(
                bold: cellStyle['bold'] == true,
                italic: cellStyle['italic'] == true,
                underline: cellStyle['underline'] == true,
                fontSize: (cellStyle['fontSize'] as num?)?.toDouble(),
                onBold: busy
                    ? null
                    : () => formatCell({'bold': cellStyle['bold'] != true}),
                onItalic: busy
                    ? null
                    : () => formatCell({'italic': cellStyle['italic'] != true}),
                onUnderline: busy
                    ? null
                    : () => formatCell({
                        'underline': cellStyle['underline'] != true,
                      }),
                onSize: busy ? null : (v) => formatCell({'fontSize': v}),
              ),
            ),
          ],
        },
        overrides: {
          'Очистить содержимое': EditorTool(
            'Очистить содержимое',
            Icons.backspace_outlined,
            onPressed: busy || book == null ? null : clearSelected,
          ),
          'Выделить диапазон': EditorTool(
            'Выделить диапазон',
            Icons.select_all,
            builder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('grid-range-input'),
                  controller: rangeInput,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Диапазон'),
                    hintText: 'A1:D10',
                  ),
                  onSubmitted: (_) {
                    if (!busy) chooseRange();
                  },
                ),
                const SizedBox(height: 12),
                if (rangeSelection != null)
                  Text(
                    '${rangeSelection!.address} · ${rangeSelection!.cellCount} ${tr(context, 'ячеек')}',
                  ),
                FilledButton.icon(
                  onPressed: busy ? null : chooseRange,
                  icon: const Icon(Icons.select_all),
                  label: const UiText('Выделить ячейки'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy || rangeSelection == null
                      ? null
                      : () => setState(() {
                          rangeSelection = null;
                          rangeInput.clear();
                        }),
                  child: const UiText('Снять выделение'),
                ),
                const SizedBox(height: 8),
                const UiText(
                  'Удерживайте ячейку, затем тяните круглые маркеры. Формат применяется ко всему диапазону.',
                ),
              ],
            ),
          ),

          'Новый лист': EditorTool(
            'Новый лист',
            Icons.add_box_outlined,
            builder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('new-sheet-name'),
                  controller: newSheetName,
                  maxLength: 31,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Имя листа'),
                    hintText: tr(context, 'Автоматически, если пусто'),
                  ),
                  onSubmitted: (_) {
                    if (!busy) addSheet();
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : addSheet,
                  icon: const Icon(Icons.add),
                  label: const UiText('Создать лист'),
                ),
              ],
            ),
          ),

          '∑ Автосумма': EditorTool(
            '∑ Автосумма',
            Icons.functions,
            onPressed: busy || book == null ? null : autoSum,
          ),
          'Пересчитать': EditorTool(
            'Пересчитать',
            Icons.refresh,
            onPressed: busy || book == null ? null : recalculate,
          ),
          'Формат ячейки': EditorTool(
            'Формат ячейки',
            Icons.numbers,
            children: [
              EditorTool(
                'Числовой формат',
                Icons.numbers,
                children: [
                  for (final format in [
                    ('Общий', 'General'),
                    ('Целое число', '0'),
                    ('Числовой', '#,##0.00'),
                    ('Денежный (₽)', '#,##0.00 "₽"'),
                    ('Процентный', '0.00%'),
                    ('Дата', 'dd.mm.yyyy'),
                    ('Время', 'hh:mm'),
                    ('Текстовый', '@'),
                  ])
                    action(format.$1, Icons.numbers, {'numFmt': format.$2}),
                ],
              ),
              EditorTool(
                'Выравнивание',
                Icons.format_align_left,
                children: [
                  action('По значению', Icons.align_horizontal_left, {
                    'align': 'general',
                  }),
                  action('Слева', Icons.format_align_left, {'align': 'left'}),
                  action('По центру', Icons.format_align_center, {
                    'align': 'center',
                  }),
                  action('Справа', Icons.format_align_right, {
                    'align': 'right',
                  }),
                  action('Сверху', Icons.vertical_align_top, {
                    'verticalAlign': 'top',
                  }),
                  action('Посередине', Icons.vertical_align_center, {
                    'verticalAlign': 'center',
                  }),
                  action('Снизу', Icons.vertical_align_bottom, {
                    'verticalAlign': 'bottom',
                  }),
                ],
              ),
              action(
                cellStyle['wrap'] == true
                    ? 'Выключить перенос текста'
                    : 'Перенос текста',
                Icons.wrap_text,
                {'wrap': cellStyle['wrap'] != true},
              ),
              colors('Цвет текста', 'color', Icons.format_color_text),
              action(
                cellStyle['shrink'] == true
                    ? 'Выключить уменьшение текста'
                    : 'Уменьшить текст по ширине',
                Icons.fit_screen,
                {'shrink': cellStyle['shrink'] != true},
              ),
            ],
          ),
          'Заливка': colors('Заливка', 'fill', Icons.format_color_fill),
          'Границы': EditorTool(
            'Границы',
            Icons.border_all,
            children: [
              action('Все границы', Icons.border_all, {'borders': 'all'}),
              action('Без границ', Icons.border_clear, {'borders': 'none'}),
            ],
          ),
          'Управление листами': EditorTool(
            'Управление листами',
            Icons.tab,
            children: [
              for (var i = 0; i < sheets.length; i++)
                EditorTool(
                  sheets[i]['name']?.toString() ?? tr(context, 'Лист'),
                  i == sheetIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  localize: false,
                  onPressed: busy ? null : () => chooseSheet(i),
                ),
            ],
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = bridge != null;
    return UnsavedChangesGuard(
      interceptBack: toolsExpanded,
      onInterceptBack: () => toolPanel.currentState?.handleBack(),
      onDiscard: widget.draft?.discard,
      dirty: modified || inputDirty,
      busy: busy,
      child: Scaffold(
        bottomNavigationBar: book != null
            ? Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: editorPanel(),
              )
            : null,
        resizeToAvoidBottomInset: true,
        appBar: toolsExpanded
            ? null
            : AppBar(
                toolbarHeight: (MediaQuery.textScalerOf(context).scale(31) + 12)
                    .clamp(72.0, 144.0)
                    .toDouble(),
                title: EditorFileTitle(
                  filename: filename,
                  status: online
                      ? (modified || inputDirty
                            ? 'XLSX · есть изменения${tr(context, widget.draft?.status ?? '')}'
                            : 'XLSX · на устройстве')
                      : 'Rust недоступен',
                  color: const Color(0xff17815c),
                ),
                actions: [
                  EditorFileMenu(
                    commands: [
                      EditorCommand(
                        'Открыть XLSX',
                        Icons.folder_open_outlined,
                        online && !busy ? open : null,
                      ),
                      EditorCommand(
                        'Сохранить копию',
                        Icons.save_outlined,
                        book != null && !busy ? save : null,
                      ),
                      EditorCommand(
                        'Новый файл',
                        Icons.note_add_outlined,
                        online && !busy ? create : null,
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          bottom: false,
          child: !online
              ? const Center(
                  child: UiText(
                    'Нет нативной GridCraft-библиотеки для Android ARM64',
                  ),
                )
              : book == null
              ? EditorWelcome(
                  icon: Icons.grid_on_outlined,
                  title: 'Таблицы',
                  openLabel: 'Открыть XLSX',
                  createLabel: 'Создать XLSX',
                  onOpen: open,
                  onCreate: create,
                  busy: busy,
                )
              : Column(
                  children: [
                    Expanded(child: grid()),
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: selected.length > 5 ? 104 : 52,
                              child: UiText(
                                selected,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xff17815c),
                                ),
                              ),
                            ),
                            if (!inputFocus.hasFocus)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: UiText(
                                  'ƒₓ',
                                  style: TextStyle(fontSize: 24),
                                ),
                              ),
                            Expanded(
                              key: const ValueKey('formula-input'),
                              child: TextField(
                                readOnly: busy,
                                controller: input,
                                focusNode: inputFocus,
                                minLines: 1,
                                maxLines: formulaExpanded ? 4 : 1,
                                decoration: InputDecoration(
                                  hintText: tr(context, 'Введите…'),
                                  contentPadding: EdgeInsets.all(12),
                                ),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => commit(),
                              ),
                            ),
                            if (inputFocus.hasFocus) ...[
                              IconButton(
                                tooltip: tr(context, 'Отменить ввод'),
                                onPressed: busy
                                    ? null
                                    : () {
                                        setState(
                                          () => input.text = currentInput,
                                        );
                                        inputFocus.unfocus();
                                      },
                                icon: const Icon(Icons.close),
                              ),
                              IconButton(
                                tooltip: tr(context, 'Применить'),
                                onPressed: busy ? null : commit,
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.green,
                                ),
                              ),
                            ] else
                              IconButton(
                                tooltip: tr(
                                  context,
                                  formulaExpanded
                                      ? 'Свернуть формулу'
                                      : 'Развернуть формулу',
                                ),
                                onPressed: () => setState(
                                  () => formulaExpanded = !formulaExpanded,
                                ),
                                icon: Icon(
                                  formulaExpanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!toolsExpanded)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < sheets.length; i++)
                              TextButton(
                                onPressed: busy ? null : () => chooseSheet(i),
                                style: TextButton.styleFrom(
                                  foregroundColor: i == sheetIndex
                                      ? const Color(0xff17815c)
                                      : null,
                                ),
                                child: Text(
                                  sheets[i]['name']?.toString() ??
                                      tr(context, 'Лист'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }
}
