import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'deckcraft_bridge.dart';

class NativeDeckScreen extends StatefulWidget {
  const NativeDeckScreen({super.key});
  @override
  State<NativeDeckScreen> createState() => _NativeDeckScreenState();
}

class _NativeDeckScreenState extends State<NativeDeckScreen> {
  late final DeckCraftBridge? engine = DeckCraftBridge.tryOpen();
  Uint8List? data;
  List<Map<String, dynamic>> slides = [];
  String filename = 'Новая презентация.pptx';
  int index = 0;
  double pageW = 960, pageH = 540;
  bool busy = false, modified = false;
  bool get loaded => data != null;
  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy || engine == null) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      message('Ошибка DeckCraft: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void load(
    Uint8List bytes, {
    String? name,
    bool changed = false,
    int selected = 0,
  }) {
    final report = engine!.inspect(bytes);
    final raw = report['slides'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('PPTX не содержит доступных слайдов');
    }
    final next = raw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    setState(() {
      data = bytes;
      slides = next;
      pageW = (report['width'] as num?)?.toDouble() ?? 960;
      pageH = (report['height'] as num?)?.toDouble() ?? 540;
      index = selected.clamp(0, next.length - 1);
      modified = changed;
      if (name != null) filename = name;
    });
  }

  Future<bool> discard() async {
    if (!modified) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Несохранённые изменения'),
            content: const Text(
              'Открыть другую презентацию без сохранения текущей?',
            ),
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

  Future<void> create() => action(() async {
    if (!await discard()) return;
    load(engine!.create(), name: 'Новая презентация.pptx', changed: true);
    message('PPTX создан через DeckCraft');
  });
  Future<void> open() => action(() async {
    if (!await discard()) return;
    final path = await FlutterFileDialog.pickFile();
    if (path == null) return;
    final file = File(path);
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Файл больше 64 МБ');
    }
    load(await file.readAsBytes(), name: importedFilename(path, 'pptx'));
    message('PPTX открыт через DeckCraft');
  });
  Future<void> save() => action(() async {
    if (!loaded) return;
    final saveName =
        '${filename.replaceFirst(RegExp(r'\.pptx$', caseSensitive: false), '')}-ArtOfficeCraft.pptx';
    final destination = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: data!,
        fileName: saveName,
        mimeTypesFilter: const [
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        ],
      ),
    );
    if (destination == null) return;
    setState(() => modified = false);
    message('Копия PPTX сохранена. Исходник не изменён.');
  });
  Future<String?> ask(String heading, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(heading),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              child: const Text('Применить'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> newSlide() => action(() async {
    final title = await ask('Заголовок нового слайда');
    if (title == null) return;
    load(
      engine!.edit(data!, {'action': 'add_slide', 'text': title}),
      selected: slides.length,
      changed: true,
    );
    message('Слайд добавлен');
  });
  Future<void> insertText() => action(() async {
    final value = await ask('Новый текстовый блок');
    if (value == null || value.trim().isEmpty) return;
    load(
      engine!.edit(data!, {
        'action': 'add_text',
        'slide': index,
        'text': value,
      }),
      selected: index,
      changed: true,
    );
    message('Текст сохранён в PPTX');
  });
  Future<void> changeText(Map<String, dynamic> shape) => action(() async {
    if (shape['editableText'] != true) return;
    final value = await ask(
      'Изменить текст',
      initial: shape['text']?.toString() ?? '',
    );
    if (value == null) return;
    load(
      engine!.edit(data!, {
        'action': 'edit_text',
        'slide': index,
        'shape': shape['id'],
        'text': value,
      }),
      selected: index,
      changed: true,
    );
    message('Текст изменён');
  });
  Future<void> removeSlide() => action(() async {
    if (slides.length <= 1) {
      message('Нельзя удалить последний слайд');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить слайд?'),
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
    load(
      engine!.edit(data!, {'action': 'delete_slide', 'slide': index}),
      selected: index == 0 ? 0 : index - 1,
      changed: true,
    );
    message('Слайд удалён');
  });
  Widget slideCanvas() {
    final current = slides[index];
    final raw = current['shapes'];
    final shapes = raw is List
        ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
        : <Map<String, dynamic>>[];
    return AspectRatio(
      aspectRatio: pageW / pageH,
      child: LayoutBuilder(
        builder: (ctx, size) => Container(
          color: Colors.white,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final shape in shapes)
                if (shape['rect'] is Map &&
                    ((shape['text']?.toString() ?? '').isNotEmpty ||
                        shape['fillRgb'] != null ||
                        shape['strokeRgb'] != null))
                  _paintShape(shape, size.maxWidth, size.maxHeight),
            ],
          ),
        ),
      ),
    );
  }

  /// Only explicitly resolved RGB colors are rendered. Theme-inherited,
  /// gradient, image, SmartArt and complex geometries are not guessed.
  Color? _rgb(Object? color) {
    if (color is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      return null;
    }
    return Color(0xff000000 | int.parse(color.substring(1), radix: 16));
  }

  Widget _paintShape(Map<String, dynamic> shape, double width, double height) {
    final r = shape['rect'] as Map;
    double read(String key) => ((r[key] as num?)?.toDouble() ?? 0);
    final x = read('x') * width / pageW;
    final y = read('y') * height / pageH;
    final w = read('w') * width / pageW;
    final h = read('h') * height / pageH;
    if (!x.isFinite ||
        !y.isFinite ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0) {
      return const SizedBox.shrink();
    }
    final fill = _rgb(shape['fillRgb']);
    final stroke = _rgb(shape['strokeRgb']);
    final text = (shape['text'] ?? '').toString();
    final editable = shape['editableText'] == true;
    final geometry = (shape['geometry'] ?? '').toString().toLowerCase();
    final isOval = geometry.contains('ellipse') || geometry.contains('oval');
    final radius = isOval
        ? BorderRadius.circular(999)
        : geometry.contains('round')
        ? BorderRadius.circular(12)
        : null;
    final ink = fill != null && fill.computeLuminance() < 0.23
        ? Colors.white
        : const Color(0xff273341);
    return Positioned(
      left: x,
      top: y,
      width: w,
      height: h,
      child: GestureDetector(
        onTap: editable ? () => changeText(shape) : null,
        child: Container(
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.all(text.isEmpty ? 0 : 4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color:
                  stroke ??
                  (editable ? const Color(0xffd4dce5) : Colors.transparent),
              width: stroke == null ? 0.7 : 1.5,
            ),
          ),
          child: text.isEmpty
              ? null
              : Text(
                  text,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: (width / 960 * 19).clamp(8.0, 24.0),
                  ),
                ),
        ),
      ),
    );
  }

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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              enabled ? 'DeckCraft Rust · PPTX' : 'Rust недоступен',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Открыть PPTX',
            onPressed: enabled && !busy ? open : null,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Сохранить копию PPTX',
            onPressed: loaded && !busy ? save : null,
            icon: const Icon(Icons.save_outlined),
          ),
          PopupMenuButton<String>(
            enabled: loaded && !busy,
            onSelected: (v) {
              if (v == 'delete') removeSlide();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Удалить слайд')),
            ],
          ),
        ],
      ),
      body: !enabled
          ? const Center(
              child: Text('DeckCraft Rust недоступен на этом устройстве'),
            )
          : !loaded
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.slideshow_outlined, size: 46),
                  const SizedBox(height: 16),
                  const Text('Редактор PPTX на DeckCraft'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: open,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Открыть PPTX'),
                  ),
                  TextButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Text('Создать PPTX'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: Text(
                    'Упрощённый предпросмотр слайдов: изображения, сложные фигуры и анимации '
                    'здесь не отображаются. Нажми текст, чтобы изменить.',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: slideCanvas(),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 90,
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: slides.length,
                    itemBuilder: (c, i) {
                      final selected = i == index;
                      final title = (slides[i]['title'] ?? '').toString();
                      final first = slides[i]['shapes'] is List
                          ? (slides[i]['shapes'] as List)
                                .whereType<Map>()
                                .map((s) => (s['text'] ?? '').toString())
                                .firstWhere(
                                  (t) => t.isNotEmpty,
                                  orElse: () => '',
                                )
                          : '';
                      return GestureDetector(
                        onTap: () => setState(() => index = i),
                        child: Container(
                          width: 138,
                          margin: const EdgeInsets.all(5),
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selected ? Colors.deepOrange : Colors.grey,
                              width: selected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  color: Colors.white,
                                  child: Text(
                                    title.isNotEmpty
                                        ? title
                                        : first.isNotEmpty
                                        ? first
                                        : 'Слайд ${i + 1}',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                  ),
                                ),
                              ),
                              Text(
                                (i + 1).toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy ? null : newSlide,
                            icon: const Icon(Icons.add),
                            label: const Text('Слайд'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : insertText,
                            icon: const Icon(Icons.text_fields),
                            label: const Text('Текст'),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Сохранить',
                          onPressed: busy ? null : save,
                          icon: const Icon(Icons.save_outlined),
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
