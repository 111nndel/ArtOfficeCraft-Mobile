import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'gridcraft_bridge.dart';

class NativeGridScreen extends StatefulWidget {
  const NativeGridScreen({super.key});
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
    setBook(bridge!.create(), name: 'Новая книга.xlsx', edited: true);
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
    height: 48,
    alignment: Alignment.center,
    color: const Color(0xff223039),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 11),
    ),
  );
  Widget cell(String address) {
    final item = cells[address];
    final value = item is Map ? item['display']?.toString() ?? '' : '';
    return InkWell(
      onTap: () => selectCell(address),
      child: Container(
        height: 48,
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
          style: const TextStyle(color: Color(0xff172634), fontSize: 13),
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
          defaultColumnWidth: const FixedColumnWidth(92),
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
  Widget build(BuildContext context) {
    final online = bridge != null;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              online ? 'GridCraft Rust · XLSX' : 'Rust недоступен',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
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
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text(
                      'Редактирование XLSX. Превью ограничено 55 строками и 12 столбцами; '
                      'сложное оформление и диаграммы пока не отображаются.',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
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
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: input,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Введите…',
                        ),
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
                if (showTabs)
                  SizedBox(
                    height: 48,
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
                SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 60,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => setState(() => showTabs = !showTabs),
                          icon: const Icon(Icons.view_carousel_outlined),
                          label: Text(
                            showTabs ? 'Скрыть листы' : 'Показать листы',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: busy ? null : create,
                          icon: const Icon(Icons.add),
                          label: const Text('Новая книга'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: busy ? null : save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Сохранить копию'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
