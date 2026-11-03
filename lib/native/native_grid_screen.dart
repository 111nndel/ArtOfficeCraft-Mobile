import '../ui/editor_tools.dart';
import 'document_backend.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';
import 'format_limits_notice.dart';

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
  late final DocumentBackend? bridge =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.grid);
  Uint8List? book;
  String filename = 'Книга.xlsx', selected = 'A1';
  int sheetIndex = 0;
  bool modified = false, busy = false, showTabs = true;
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
  List<EditorCommand> get commands => [
    EditorCommand(
      'Ввести значение',
      Icons.edit_outlined,
      book != null && !busy ? () => inputFocus.requestFocus() : null,
    ),
    EditorCommand(
      'Применить',
      Icons.check,
      book != null && !busy ? commit : null,
    ),
    EditorCommand(
      'Скрыть / показать листы',
      Icons.tab,
      book != null && !busy ? () => setState(() => showTabs = !showTabs) : null,
    ),
    EditorCommand(
      'Сохранить копию',
      Icons.save_outlined,
      book != null && !busy ? save : null,
    ),
  ];
  final inputFocus = FocusNode();
  Widget header(String text) => Container(
    height: 56,
    alignment: Alignment.center,
    color: const Color(0xff223039),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 14),
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
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: address == selected ? const Color(0xffe3f2ea) : Colors.white,
          border: address == selected
              ? Border.all(color: const Color(0xff188458), width: 2)
              : null,
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

  @override
  Widget build(BuildContext context) {
    final online = bridge != null;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = MediaQuery.sizeOf(context).height < 650;
    return UnsavedChangesGuard(
      dirty: modified,
      busy: busy,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: (MediaQuery.textScalerOf(context).scale(31) + 12)
              .clamp(72.0, 144.0)
              .toDouble(),
          title: EditorFileTitle(
            filename: filename,
            status: online ? 'GridCraft Rust · XLSX' : 'Rust недоступен',
            color: const Color(0xff17815c),
          ),
          bottom: keyboardOpen
              ? null
              : EditorSectionTabs(
                  color: const Color(0xff17815c),
                  height: (MediaQuery.textScalerOf(context).scale(16) + 30)
                      .clamp(56.0, 90.0),
                  sections: [
                    EditorToolSection('Главная', commands),
                    EditorToolSection('Формулы', commands),
                    EditorToolSection('Файл', [
                      EditorCommand(
                        'Открыть XLSX',
                        Icons.folder_open,
                        online && !busy ? open : null,
                      ),
                      commands.last,
                    ]),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: 'Открыть XLSX',
              onPressed: online && !busy ? open : null,
              icon: const Icon(Icons.folder_open_outlined),
            ),
            IconButton(
              tooltip: 'Сохранить копию',
              onPressed: book != null && !busy ? save : null,
              icon: const Icon(Icons.save_outlined),
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
                  if (!keyboardOpen && !compact)
                    const FormatLimitsNotice(
                      summary: 'XLSX · ограничения просмотра',
                      details:
                          'Показаны 55 строк и 12 столбцов. Сложное '
                          'оформление и диаграммы пока не отображаются.',
                    ),
                  Expanded(child: grid()),
                  Row(
                    children: [
                      const Tooltip(
                        message: 'Число, текст или формула со знака =',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('ƒₓ', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      Text(
                        selected,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: input,
                          focusNode: inputFocus,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Введите…',
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => commit(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Отменить ввод',
                        onPressed: busy
                            ? null
                            : () => setState(() => input.text = currentInput),
                        icon: const Icon(Icons.close),
                      ),
                      IconButton(
                        tooltip: 'Применить',
                        onPressed: busy ? null : commit,
                        icon: const Icon(Icons.check, color: Colors.green),
                      ),
                    ],
                  ),
                  if (showTabs && !keyboardOpen && !compact)
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (int i = 0; i < sheets.length; i++)
                            TextButton(
                              onPressed: busy ? null : () => chooseSheet(i),
                              child: Text(
                                sheets[i]['name']?.toString() ?? 'Лист',
                                style: TextStyle(
                                  fontWeight: i == sheetIndex
                                      ? FontWeight.bold
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (!keyboardOpen)
                    EditorCommandBar(
                      commands: commands,
                      color: const Color(0xff17815c),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
      ),
    );
  }
}
