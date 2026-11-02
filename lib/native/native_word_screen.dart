import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'wordcraft_bridge.dart';

/// Real DOCX read/append/save path, not a full Word layout renderer.
class NativeWordScreen extends StatefulWidget {
  const NativeWordScreen({super.key});
  @override
  State<NativeWordScreen> createState() => _NativeWordScreenState();
}

class _NativeWordScreenState extends State<NativeWordScreen> {
  late final WordCraftBridge? engine = WordCraftBridge.tryOpen();
  final TextEditingController paragraph = TextEditingController();
  Uint8List? document;
  List<String> paragraphs = [];
  String filename = 'Документ.docx';
  int tables = 0;
  bool changed = false;
  bool busy = false;

  @override
  void dispose() {
    paragraph.dispose();
    super.dispose();
  }

  void inform(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  void updatePreview(Uint8List bytes) {
    final summary = engine!.inspect(bytes);
    final lines = summary['paragraphs'];
    if (lines is! List) {
      throw const FormatException('WordCraft не вернул абзацы');
    }
    setState(() {
      document = bytes;
      paragraphs = lines.map((item) => item.toString()).toList();
      tables = (summary['tables'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> guarded(Future<void> Function() action) async {
    if (busy || engine == null) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      inform('Операция не выполнена: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createNew() => guarded(() async {
    final bytes = engine!.create('');
    updatePreview(bytes);
    setState(() {
      filename = 'Новый документ.docx';
      changed = true;
    });
    inform('Новый DOCX создан в WordCraft. Сохраните копию на устройство.');
  });

  Future<void> openDocument() => guarded(() async {
    if (changed && document != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Несохранённые изменения'),
          content: const Text(
            'Изменения текущего документа не сохранены. Открыть другой файл?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    final selected = await FlutterFileDialog.pickFile();
    if (selected == null) return;
    final file = File(selected);
    final data = await file.readAsBytes();
    if (data.length > 64 * 1024 * 1024) {
      throw const FormatException(
        'Максимальный размер DOCX для этой сборки — 64 МБ',
      );
    }
    updatePreview(data);
    setState(() {
      filename = selected.split(Platform.pathSeparator).last;
      if (!filename.toLowerCase().endsWith('.docx')) {
        filename = 'Импортированный.docx';
      }
      changed = false;
    });
    inform('Файл открыт локальным движком WordCraft');
  });

  Future<void> appendParagraph() => guarded(() async {
    if (document == null) {
      inform('Сначала создайте или откройте DOCX');
      return;
    }
    final value = paragraph.text.trim();
    if (value.isEmpty) return;
    final bytes = engine!.appendParagraph(document!, value);
    updatePreview(bytes);
    setState(() {
      changed = true;
      paragraph.clear();
    });
    inform('Абзац добавлен в модель документа WordCraft');
  });

  Future<void> saveAs() => guarded(() async {
    if (document == null) return;
    final bytes = document!;
    final suggested =
        '${filename.replaceFirst(RegExp(r'\.docx$', caseSensitive: false), '')}-ArtOfficeCraft.docx';
    // Android SAF requests a new output destination; original never overwritten.
    final path = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: bytes,
        fileName: suggested,
        mimeTypesFilter: const [
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ],
      ),
    );
    if (path == null) return;
    setState(() => changed = false);
    inform('DOCX сохранён в выбранное место');
  });

  @override
  Widget build(BuildContext context) {
    final enabled = engine != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              enabled ? 'WordCraft Rust · DOCX' : 'Rust недоступен',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Открыть DOCX',
            onPressed: enabled && !busy ? openDocument : null,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Сохранить как DOCX',
            onPressed: enabled && !busy && document != null ? saveAs : null,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!enabled)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Нативная библиотека libartoffice_core.so недоступна. '
                'Для реального DOCX требуется Android ARM64.',
              ),
            ),
          if (enabled && document == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text('Работа с DOCX через Rust WordCraft'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: busy ? null : openDocument,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Открыть DOCX'),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : createNew,
                      icon: const Icon(Icons.add),
                      label: const Text('Новый DOCX'),
                    ),
                  ],
                ),
              ),
            )
          else if (document != null) ...[
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Текстовый предпросмотр: таблицы ($tables), изображения и точная вёрстка '
                        'пока не отображаются. Изменять существующий текст в этой сборке нельзя.',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: const Color(0xffdce1e8),
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      constraints: const BoxConstraints(minHeight: 480),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 32,
                      ),
                      color: Colors.white,
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final line in paragraphs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  line,
                                  textAlign: TextAlign.justify,
                                  style: const TextStyle(
                                    fontFamily: 'serif',
                                    color: Color(0xff27313d),
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: paragraph,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        labelText: 'Новый абзац',
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: !busy ? appendParagraph : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Добавить абзац'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: !busy ? saveAs : null,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Сохранить копию'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
