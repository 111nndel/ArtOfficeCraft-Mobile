import '../l10n/app_strings.dart';
import '../ui/sheet_viewport.dart';
import '../workspace/draft_store.dart';

import 'dart:async';

import 'document_history.dart';
import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import 'document_backend.dart';
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
    this.draft,
    this.backend,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
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
  bool formulaExpanded = false;
  late final DocumentBackend? bridge =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.grid);
  Uint8List? book;
  String filename = 'Книга.xlsx', selected = 'A1';
  int sheetIndex = 0;
  bool modified = false, busy = false;
  final input = TextEditingController();
  final history = DocumentHistory();
  bool get inputDirty => input.text != currentInput;
  Map<String, dynamic> get cellStyle => Map<String, dynamic>.from(
    (cells[selected] as Map?)?['style'] as Map? ?? {},
  );
  List<Map<String, dynamic>> sheets = [];
  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
    inputFocus.dispose();
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
    final value = cells[selected];
    return value is Map ? value['input']?.toString() ?? '' : '';
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
    }
  }

  Future<void> setBook(
    Uint8List data, {
    String? name,
    bool edited = false,
    int index = 0,
  }) async {
    data = immutableDocumentBytes(data);
    final parsed = await bridge!.inspect(data);
    if (!mounted) return;
    final list = parsed['sheets'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('Листы не найдены');
    }
    setState(() {
      book = data;
      sheets = list.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      sheetIndex = index.clamp(0, sheets.length - 1);
      selected = 'A1';
      refreshCells();
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
  });
  Future<void> open() => run(() async {
    if (!await askDiscard()) return;
    final path = await FlutterFileDialog.pickFile();
    if (path == null) return;
    final file = File(path);
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Размер файла более 64 МБ');
    }
    final name = importedFilename(path, 'xlsx');
    await setBook(await file.readAsBytes(), name: name);
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

  void install(Uint8List bytes, List<Map<String, dynamic>> list) {
    setState(() {
      book = bytes;
      sheets = list;
      sheetIndex = sheetIndex.clamp(0, list.length - 1);
      refreshCells();
      input.text = currentInput;
      modified = true;
    });
  }

  Future<void> applyEdit(Map<String, dynamic> request) async {
    final previous = book!;
    final updated = await bridge!.editAndInspect(previous, request);
    final parsed = parsedSheets(updated.preview);
    if (!mounted) return;
    history.push(previous);
    install(updated.bytes, parsed);
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
  Future<void> selectCell(String address) => run(() async {
    if (address == selected) return;
    await flushInput();
    if (!mounted) return;
    setState(() {
      selected = address;
      input.text = currentInput;
    });
  });
  Future<void> chooseSheet(int idx) => run(() async {
    if (idx == sheetIndex) return;
    await flushInput();
    if (!mounted) return;
    setState(() {
      sheetIndex = idx;
      selected = 'A1';
      refreshCells();
      input.text = currentInput;
    });
  });
  Future<void> formatCell(Map<String, dynamic> style) => run(() async {
    if (book == null) return;
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
    final parsed = parsedSheets(await bridge!.inspect(target));
    if (!mounted) return;
    if (undo) {
      history.undo(book!);
    } else {
      history.redo(book!);
    }
    install(target, parsed);
    await rememberCurrent();
  });
  final inputFocus = FocusNode();
  Widget header(String text) => Container(
    height: 56,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Color(0xfff5f7fa),
      border: Border(
        right: BorderSide(color: Color(0xffe5e9ef)),
        bottom: BorderSide(color: Color(0xffe5e9ef)),
      ),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xff7c8694), fontSize: 14),
    ),
  );
  Widget cell(String address) {
    final item = cells[address];
    final value = item is Map ? item['display']?.toString() ?? '' : '';
    final style = Map<String, dynamic>.from(
      item is Map ? item['style'] as Map? ?? {} : {},
    );
    final numeric = item is Map && item['numeric'] == true;
    final fill = rgb(style['fill']) ?? Colors.white;
    return InkWell(
      key: ValueKey('grid-cell-$address'),
      onTap: busy ? null : () => selectCell(address),
      child: Container(
        height: 56,
        alignment: switch (style['align']) {
          'left' => Alignment.centerLeft,
          'center' => Alignment.center,
          'right' => Alignment.centerRight,
          _ =>
            numeric || double.tryParse(value.replaceAll(' ', '')) != null
                ? Alignment.centerRight
                : Alignment.centerLeft,
        },
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
        child: Text(
          value,
          textAlign: switch (style['align']) {
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            _ => TextAlign.left,
          },
          style: TextStyle(
            color: rgb(style['color']) ?? const Color(0xff172634),
            fontSize: ((style['fontSize'] as num?)?.toDouble() ?? 12) * 1.33,
            fontWeight: style['bold'] == true
                ? FontWeight.bold
                : FontWeight.normal,
            fontStyle: style['italic'] == true
                ? FontStyle.italic
                : FontStyle.normal,
            decoration: style['underline'] == true
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
          maxLines: style['wrap'] == true ? 3 : 1,
          overflow: TextOverflow.clip,
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
          : const Color(0xffe5e9ef),
      width: width > 0 ? width.clamp(1, 3).toDouble() : .7,
    );
  }

  final gridViewport = GlobalKey<SheetViewportState>();
  Widget grid() => SheetViewport(
    key: gridViewport,
    width: 52 + 12 * 116,
    rowCount: 55,
    header: Row(
      children: [
        SizedBox(width: 52, child: header('')),
        for (var c = 0; c < 12; c++)
          SizedBox(width: 116, child: header(String.fromCharCode(65 + c))),
      ],
    ),
    rowBuilder: (context, index) => Row(
      children: [
        SizedBox(width: 52, child: header('${index + 1}')),
        for (var c = 0; c < 12; c++)
          SizedBox(
            width: 116,
            child: cell('${String.fromCharCode(65 + c)}${index + 1}'),
          ),
      ],
    ),
  );
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
            restoreDraft(request.recovery);
            if (request.recovery == null) await rememberCurrent();
          });
        } else if (request.create) {
          create();
        }
      });
    }
  }

  void restoreDraft(Map<String, dynamic>? state) {
    if (state == null) return;
    final sheet = state['sheet'] as int;
    final address = state['selected'] as String;
    if (sheet < 0 ||
        sheet >= sheets.length ||
        !RegExp(r'^[A-Z]{1,3}[1-9][0-9]{0,6}$').hasMatch(address)) {
      throw const FormatException(
        'Не удалось восстановить выбранную ячейку. Черновик сохранён.',
      );
    }
    sheetIndex = sheet;
    selected = address;
    refreshCells();
    input.text = state['input'] as String;
    modified = state['modified'] == true;
    restoringDraft = false;
    setState(() {});
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
        exclude: {'Ж'},
        leading: {
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
          'Масштаб': EditorTool(
            'Масштаб',
            Icons.zoom_in,
            children: [
              for (final percent in [50, 75, 100, 125, 150, 200, 300])
                EditorTool(
                  '$percent%',
                  Icons.zoom_in,
                  onPressed: () =>
                      gridViewport.currentState?.setZoom(percent / 100),
                ),
            ],
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
                              width: 52,
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
