import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';
import 'format_limits_notice.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';
import 'gridcraft_bridge.dart';

class NativeGridScreen extends StatefulWidget {
  const NativeGridScreen({super.key, this.launch, this.onRemember});
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  @override
  State<NativeGridScreen> createState() => _NativeGridScreenState();
}

class _NativeGridScreenState extends State<NativeGridScreen> {
  late final GridCraftBridge? bridge = GridCraftBridge.tryOpen();
  Uint8List? book;
  String filename = 'Книга.xlsx', selected = 'A1';
  int sheetIndex = 0;
  bool modified = false, busy = false, showTabs = true;
  final input = TextEditingController();
  List<Map<String, dynamic>> sheets = [];
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Map<String, dynamic> get cells => sheets.isNotEmpty
      ? Map<String, dynamic>.from(sheets[sheetIndex]['cells'] as Map)
      : {};
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

  void setBook(
    Uint8List data, {
    String? name,
    bool edited = false,
    int index = 0,
  }) {
    final parsed = bridge!.inspect(data);
    final list = parsed['sheets'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('Листы не найдены');
    }
    setState(() {
      book = data;
      sheets = list.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      sheetIndex = index.clamp(0, sheets.length - 1);
      selected = 'A1';
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
    var bytes = bridge!.create();
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
        bytes = bridge!.editCell(bytes, 0, entry.key, entry.value);
      }
    }
    setBook(
      bytes,
      name: widget.launch?.template == true
          ? 'Бюджет команды.xlsx'
          : 'Новая книга.xlsx',
      edited: true,
    );
    tip('XLSX создан через GridCraft');
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
    setBook(await file.readAsBytes(), name: name);
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
    final updated = bridge!.editCell(book!, idx, before, input.text);
    final parsed = bridge!.inspect(updated);
    final list = parsed['sheets'] as List;
    setState(() {
      book = updated;
      sheets = list.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      modified = true;
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
    input.text = currentInput;
  });
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
      onTap: () => selectCell(address),
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

  Widget grid() => ColoredBox(
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(116),
          border: TableBorder.all(color: const Color(0xffd5dde1), width: .7),
          children: [
            TableRow(
              children: [
                header(''),
                for (int c = 0; c < 12; c++)
                  header(String.fromCharCode(65 + c)),
              ],
            ),
            for (int r = 1; r <= 55; r++)
              TableRow(
                children: [
                  header(r.toString()),
                  for (int c = 0; c < 12; c++)
                    cell(String.fromCharCode(65 + c) + r.toString()),
                ],
              ),
          ],
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
            setBook(request.bytes!, name: request.name);
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
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.grid_on_outlined, size: 46),
                    const SizedBox(height: 12),
                    const Text('GridCraft — редактор XLSX'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: open,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Открыть XLSX'),
                    ),
                    TextButton.icon(
                      onPressed: create,
                      icon: const Icon(Icons.add),
                      label: const Text('Создать XLSX'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (!keyboardOpen)
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
                  if (showTabs && !keyboardOpen)
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (int i = 0; i < sheets.length; i++)
                            TextButton(
                              onPressed: () => chooseSheet(i),
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
                    SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 68,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => showTabs = !showTabs),
                              icon: const Icon(Icons.view_carousel_outlined),
                              label: Text(
                                showTabs ? 'Скрыть листы' : 'Показать листы',
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: busy ? null : create,
                              icon: const Icon(Icons.add),
                              label: const Text('Новая книга'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: busy ? null : save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Сохранить копию'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 52),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
      ),
    );
  }
}
