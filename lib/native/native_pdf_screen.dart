import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'pdfcraft_bridge.dart';

class NativePdfScreen extends StatefulWidget {
  const NativePdfScreen({super.key});
  @override
  State<NativePdfScreen> createState() => _NativePdfScreenState();
}

class _NativePdfScreenState extends State<NativePdfScreen> {
  late final PdfCraftBridge? engine = PdfCraftBridge.tryOpen();
  Uint8List? contents;
  List<Map<String, dynamic>> pages = [];
  String filename = 'Новый документ.pdf';
  int selected = 0;
  bool busy = false, changed = false;

  void tip(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> execute(Future<void> Function() task) async {
    if (busy || engine == null) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      tip('PDFCraft: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void load(Uint8List data, {String? name, bool edited = false, int page = 0}) {
    final summary = engine!.inspect(data);
    final raw = summary['pages'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Страницы PDF не найдены');
    }
    setState(() {
      contents = data;
      pages = raw.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      selected = page.clamp(0, pages.length - 1);
      changed = edited;
      if (name != null) filename = name;
    });
  }

  Future<bool> discard() async {
    if (!changed) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Несохранённые изменения'),
            content: const Text('Заменить текущий PDF без сохранения копии?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Продолжить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> create() => execute(() async {
    if (!await discard()) return;
    load(engine!.create(), name: 'Новый документ.pdf', edited: true);
    tip('Создан PDF с одной страницей');
  });
  Future<void> open() => execute(() async {
    if (!await discard()) return;
    final path = await FlutterFileDialog.pickFile();
    if (path == null) return;
    final f = File(path);
    if (await f.length() > 64 * 1024 * 1024) {
      throw const FormatException('Слишком большой PDF (>64 МБ)');
    }
    if (!path.toLowerCase().endsWith('.pdf')) {
      throw const FormatException('Ожидается PDF');
    }
    load(await f.readAsBytes(), name: path.split(Platform.pathSeparator).last);
    tip('Структура PDF прочитана');
  });
  Future<void> save() => execute(() async {
    if (contents == null) return;
    final name =
        '${filename.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}-ArtOfficeCraft.pdf';
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: contents!,
        fileName: name,
        mimeTypesFilter: const ['application/pdf'],
      ),
    );
    if (path == null) return;
    setState(() => changed = false);
    tip('Копия PDF сохранена. Подписи могут стать недействительными.');
  });
  Future<void> edit(String action) async {
    if (contents == null) return;
    if (action == 'delete') {
      if (pages.length <= 1) {
        tip('Последнюю страницу удалить нельзя');
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Удалить страницу?'),
          content: const Text(
            'Оригинал PDF не изменяется, сохранение только в новую копию.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await execute(() async {
      final updated = engine!.edit(contents!, {
        'action': action,
        'page': selected,
      });
      var next = selected;
      if (action == 'move_up') next--;
      if (action == 'move_down' ||
          action == 'duplicate' ||
          action == 'insert_blank') {
        next++;
      }
      load(updated, page: next, edited: true);
      tip('Структура PDF изменена');
    });
  }

  Widget pageThumb(int i) {
    final p = pages[i];
    return GestureDetector(
      onTap: () => setState(() => selected = i),
      child: Container(
        width: 110,
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          border: Border.all(
            color: i == selected ? Colors.deepOrange : Colors.grey,
            width: i == selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: Text(
                  (i + 1).toString(),
                  style: const TextStyle(fontSize: 24, color: Colors.black54),
                ),
              ),
            ),
            Text(
              'Стр. ${i + 1} · ${p['rotation']}°',
              style: const TextStyle(fontSize: 10),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = engine != null;
    return Scaffold(
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
              available ? 'PDFCraft Rust · PDF' : 'Rust недоступен',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Открыть PDF',
            onPressed: available && !busy ? open : null,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Сохранить PDF',
            onPressed: contents != null && !busy ? save : null,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: !available
          ? const Center(child: Text('PDFCraft Rust недоступен'))
          : contents == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, size: 50),
                  const SizedBox(height: 12),
                  const Text('PDFCraft — работа со страницами'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: open,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Открыть PDF'),
                  ),
                  TextButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Text('Новый PDF'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Управление страницами PDF. Содержимое пока не отображается. '
                      'Сложные файлы и цифровые подписи требуют дополнительной проверки.',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: .707,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 8),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.description_outlined,
                                size: 60,
                                color: Colors.black26,
                              ),
                              Text(
                                'Страница ${selected + 1} из ${pages.length}',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Просмотр содержимого ещё не реализован',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                'Поворот: ${pages[selected]['rotation']}°',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 114,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: pages.length,
                    itemBuilder: (c, i) => pageThumb(i),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 3,
                    runSpacing: 1,
                    children: [
                      IconButton(
                        tooltip: 'Переместить назад',
                        onPressed: busy || selected == 0
                            ? null
                            : () => edit('move_up'),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      IconButton(
                        tooltip: 'Переместить вперёд',
                        onPressed: busy || selected == pages.length - 1
                            ? null
                            : () => edit('move_down'),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                      IconButton(
                        tooltip: 'Повернуть влево',
                        onPressed: busy ? null : () => edit('rotate_ccw'),
                        icon: const Icon(Icons.rotate_left),
                      ),
                      IconButton(
                        tooltip: 'Повернуть вправо',
                        onPressed: busy ? null : () => edit('rotate_cw'),
                        icon: const Icon(Icons.rotate_right),
                      ),
                      IconButton(
                        tooltip: 'Дублировать страницу',
                        onPressed: busy ? null : () => edit('duplicate'),
                        icon: const Icon(Icons.copy),
                      ),
                      IconButton(
                        tooltip: 'Вставить пустую страницу',
                        onPressed: busy ? null : () => edit('insert_blank'),
                        icon: const Icon(Icons.note_add_outlined),
                      ),
                      IconButton(
                        tooltip: 'Удалить страницу',
                        onPressed: busy || pages.length <= 1
                            ? null
                            : () => edit('delete'),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
