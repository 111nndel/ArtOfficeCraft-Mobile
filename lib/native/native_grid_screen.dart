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
    this.backend,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  final DocumentBackend? backend;
  @override
  State<NativeGridScreen> createState() => _NativeGridScreenState();
}

class _NativeGridScreenState extends State<NativeGridScreen> {
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
  List<Map<String, dynamic>> sheets = [];
  @override
  void dispose() {
    inputFocus.dispose();
    input.dispose();
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
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
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
    }
  }

  Future<void> setBook(
    Uint8List data, {
    String? name,
    bool edited = false,
    int index = 0,
  }) async {
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
    });
  }

  Future<bool> askDiscard() async {
    if (!modified) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Изменения не сохранены'),
        content: const Text('Открыть другую книгу без сохранения этой?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    return choice == true;
  }

  Future<void> create() => run(() async {
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
          'value': entry.value,
        });
      }
    }
    await setBook(
      bytes,
      name: widget.launch?.template == true
          ? 'Бюджет команды.xlsx'
          : 'Новая книга.xlsx',
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
    if (book == null) return;
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
  Future<void> commit() => run(() async {
    if (book == null) return;
    final before = selected;
    final idx = sheetIndex;
    final updated = await bridge!.edit(book!, {
      'sheet': idx,
      'address': before,
      'value': input.text,
    });
    final parsed = await bridge!.inspect(updated);
    if (!mounted) return;
    final list = parsed['sheets'] as List;
    setState(() {
      book = updated;
      sheets = list.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      modified = true;
      refreshCells();
      input.text = currentInput;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    tip('Ячейка $before сохранена в модели XLSX');
  });
  void selectCell(String a1) => setState(() {
    selected = a1;
    input.text = currentInput;
  });
  void chooseSheet(int idx) => setState(() {
    sheetIndex = idx;
    selected = 'A1';
    refreshCells();
    input.text = currentInput;
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
    return InkWell(
      key: ValueKey('grid-cell-$address'),
      onTap: busy ? null : () => selectCell(address),
      child: Container(
        height: 56,
        alignment: double.tryParse(value.replaceAll(' ', '')) != null
            ? Alignment.centerRight
            : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: address == selected ? const Color(0xffe3f2ea) : Colors.white,
          border: address == selected
              ? Border.all(color: const Color(0xff188458), width: 2)
              : const Border(
                  right: BorderSide(color: Color(0xffe5e9ef)),
                  bottom: BorderSide(color: Color(0xffe5e9ef)),
                ),
        ),
        child: Text(
          value,
          style: const TextStyle(color: Color(0xff172634), fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }

  Widget grid() => LayoutBuilder(
    builder: (context, constraints) => ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 52 + 12 * 116,
          child: Column(
            children: [
              if (constraints.maxHeight > 100)
                Row(
                  children: [
                    SizedBox(width: 52, child: header('')),
                    for (var c = 0; c < 12; c++)
                      SizedBox(
                        width: 116,
                        child: header(String.fromCharCode(65 + c)),
                      ),
                  ],
                ),
              Expanded(
                child: ListView.builder(
                  key: const Key('grid-rows'),
                  itemCount: 55,
                  itemExtent: 56,
                  itemBuilder: (context, index) => DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xffe4e8ee)),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 52, child: header('${index + 1}')),
                        for (var c = 0; c < 12; c++)
                          SizedBox(
                            width: 116,
                            child: cell(
                              '${String.fromCharCode(65 + c)}${index + 1}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  void initState() {
    super.initState();
    inputFocus.addListener(() {
      if (mounted) setState(() {});
    });
    final request = widget.launch;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (request.bytes != null) {
          run(() async {
            await setBook(request.bytes!, name: request.name);
            await rememberCurrent();
          });
        } else if (request.create) {
          create();
        }
      });
    }
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

  Widget editorPanel() => EditorToolPanel(
    key: toolPanel,
    color: const Color(0xff17815c),
    onExpandedChanged: (value) => setState(() => toolsExpanded = value),
    sections: officeSections(
      'grid',
      exclude: {'Ж'},
      leading: {
        'Главная': [
          const EditorTool(
            'Стиль',
            Icons.text_fields,
            inline: true,
            builder: _gridStyles,
          ),
        ],
      },
      overrides: {
        'Управление листами': EditorTool(
          'Управление листами',
          Icons.tab,
          children: [
            for (var i = 0; i < sheets.length; i++)
              EditorTool(
                sheets[i]['name']?.toString() ?? 'Лист',
                i == sheetIndex
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                onPressed: busy ? null : () => chooseSheet(i),
              ),
          ],
        ),
      },
    ),
  );
  static Widget _gridStyles(BuildContext context) =>
      const EditorTextStyleControls();

  @override
  Widget build(BuildContext context) {
    final online = bridge != null;
    return UnsavedChangesGuard(
      interceptBack: toolsExpanded,
      onInterceptBack: () => toolPanel.currentState?.handleBack(),
      dirty: modified,
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
                      ? (modified
                            ? 'XLSX · есть изменения'
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
        body: !online
            ? const Center(
                child: Text(
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
                            child: Text(
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
                              child: Text('ƒₓ', style: TextStyle(fontSize: 24)),
                            ),
                          Expanded(
                            key: const ValueKey('formula-input'),
                            child: TextField(
                              controller: input,
                              focusNode: inputFocus,
                              minLines: 1,
                              maxLines: formulaExpanded ? 4 : 1,
                              decoration: const InputDecoration(
                                hintText: 'Введите…',
                                contentPadding: EdgeInsets.all(12),
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => commit(),
                            ),
                          ),
                          if (inputFocus.hasFocus) ...[
                            IconButton(
                              tooltip: 'Отменить ввод',
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() => input.text = currentInput);
                                      inputFocus.unfocus();
                                    },
                              icon: const Icon(Icons.close),
                            ),
                            IconButton(
                              tooltip: 'Применить',
                              onPressed: busy ? null : commit,
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                            ),
                          ] else
                            IconButton(
                              tooltip: formulaExpanded
                                  ? 'Свернуть формулу'
                                  : 'Развернуть формулу',
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
                                sheets[i]['name']?.toString() ?? 'Лист',
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
      ),
    );
  }
}
