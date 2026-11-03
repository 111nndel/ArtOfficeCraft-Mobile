import '../ui/editor_tools.dart';
import 'document_backend.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';
import 'format_limits_notice.dart';

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';
import 'deckcraft_bridge.dart';
import 'deck_text_dialog.dart';

class NativeDeckScreen extends StatefulWidget {
  const NativeDeckScreen({
    super.key,
    this.launch,
    this.onRemember,
    this.backend,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  final DocumentBackend? backend;
  @override
  State<NativeDeckScreen> createState() => _NativeDeckScreenState();
}

class _NativeDeckScreenState extends State<NativeDeckScreen> {
  late final DocumentBackend? engine =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.deck);
  Uint8List? data;
  List<Map<String, dynamic>> slides = [];
  String filename = 'Новая презентация.pptx';
  int index = 0;
  double pageW = 960, pageH = 540;
  bool busy = false, modified = false;
  // Bounded per-document Future cache. Parsing and extracting image bytes
  // runs off the Flutter UI isolate, and never performs network requests.
  final Map<String, Future<Uint8List?>> _pictures = {};
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

  Future<void> load(
    Uint8List bytes, {
    String? name,
    bool changed = false,
    int selected = 0,
  }) async {
    final report = await engine!.inspect(bytes);
    if (!mounted) return;
    final raw = report['slides'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('PPTX не содержит доступных слайдов');
    }
    final next = raw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    setState(() {
      data = bytes;
      _pictures.clear();
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
    var bytes = await engine!.create();
    if (widget.launch?.template == true) {
      bytes = await engine!.edit(bytes, {
        'action': 'add_text',
        'slide': 0,
        'text': 'Идея, которая объединяет.',
      });
      bytes = await engine!.edit(bytes, {
        'action': 'add_slide',
        'text': 'От идеи — к действию',
      });
      bytes = await engine!.edit(bytes, {
        'action': 'add_slide',
        'text': 'Следующий шаг',
      });
    }
    await load(
      bytes,
      name: widget.launch?.template == true
          ? 'Презентация идеи.pptx'
          : 'Новая презентация.pptx',
      changed: true,
    );
  });
  Future<void> open() => action(() async {
    if (!await discard()) return;
    final path = await FlutterFileDialog.pickFile();
    if (path == null) return;
    final file = File(path);
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Файл больше 64 МБ');
    }
    await load(await file.readAsBytes(), name: importedFilename(path, 'pptx'));
    await rememberCurrent();
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
    await rememberCurrent();
    message('Копия PPTX сохранена. Исходник не изменён.');
  });
  Future<String?> ask(String heading, {String initial = ''}) =>
      showDeckTextDialog(context, heading, initial: initial);

  Future<void> newSlide() => action(() async {
    final title = await ask('Заголовок нового слайда');
    if (title == null) return;
    await load(
      await engine!.edit(data!, {'action': 'add_slide', 'text': title}),
      selected: slides.length,
      changed: true,
    );
    message('Слайд добавлен');
  });
  Future<void> insertText() => action(() async {
    final value = await ask('Новый текстовый блок');
    if (value == null || value.trim().isEmpty) return;
    await load(
      await engine!.edit(data!, {
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
    await load(
      await engine!.edit(data!, {
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
    await load(
      await engine!.edit(data!, {'action': 'delete_slide', 'slide': index}),
      selected: index == 0 ? 0 : index - 1,
      changed: true,
    );
    message('Слайд удалён');
  });
  Future<void> chooseTextObject() async {
    final shapes = (slides[index]['shapes'] as List? ?? [])
        .where((x) => x['editableText'] == true)
        .toList();
    final shape = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Текстовые объекты',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              for (final shape in shapes)
                ListTile(
                  minTileHeight: 60,
                  leading: const Icon(Icons.text_fields),
                  title: Text(
                    shape['text']?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    Map<String, dynamic>.from(shape as Map),
                  ),
                ),
              if (shapes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Текстовых объектов пока нет. Добавьте текст.'),
                ),
            ],
          ),
        ),
      ),
    );
    if (shape != null && mounted) await changeText(shape);
  }

  List<EditorCommand> get commands => [
    EditorCommand(
      'Текстовые объекты',
      Icons.list_alt,
      loaded && !busy ? chooseTextObject : null,
    ),
    EditorCommand('Новый слайд', Icons.add, loaded && !busy ? newSlide : null),
    EditorCommand(
      'Добавить текст',
      Icons.text_fields,
      loaded && !busy ? insertText : null,
    ),
    EditorCommand(
      'Удалить слайд',
      Icons.delete_outline,
      loaded && !busy && slides.length > 1 ? removeSlide : null,
    ),
    EditorCommand(
      'Сохранить копию',
      Icons.save_outlined,
      loaded && !busy ? save : null,
    ),
  ];
  Widget slideCanvas({int? slideIndex}) {
    final slideNumber = slideIndex ?? index;
    final current = slides[slideNumber];
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
                        shape['strokeRgb'] != null ||
                        shape['imageId'] is int))
                  _paintShape(
                    shape,
                    size.maxWidth,
                    size.maxHeight,
                    slide: slideNumber,
                    interactive: slideIndex == null,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List?> _picture(int slide, int mediaId) {
    final key = '$slide:$mediaId';
    final old = _pictures[key];
    if (old != null) return old;
    // Bounded pending/completed cache; avoid decoding a large media catalogue.
    if (_pictures.length >= 12 || data == null) {
      return Future<Uint8List?>.value(null);
    }
    final document = data!;
    final future = Isolate.run<Uint8List?>(() {
      final bridge = DeckCraftBridge.tryOpen();
      if (bridge == null) return null;
      try {
        return bridge.image(document, slide, mediaId);
      } catch (_) {
        // Unsupported picture: show a placeholder instead of crashing.
        return null;
      }
    });
    _pictures[key] = future;
    return future;
  }

  /// Only explicitly resolved RGB colors are rendered. Theme-inherited,
  /// gradient, image, SmartArt and complex geometries are not guessed.
  Color? _rgb(Object? color) {
    if (color is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      return null;
    }
    return Color(0xff000000 | int.parse(color.substring(1), radix: 16));
  }

  Widget _paintShape(
    Map<String, dynamic> shape,
    double width,
    double height, {
    required int slide,
    required bool interactive,
  }) {
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
        onTap: interactive && editable ? () => changeText(shape) : null,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shape['imageId'] case final int id)
                FutureBuilder<Uint8List?>(
                  future: _picture(slide, id),
                  builder: (context, snapshot) {
                    final pixels = snapshot.data;
                    if (pixels == null) {
                      return const Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.black26,
                          size: 18,
                        ),
                      );
                    }
                    return Image.memory(
                      pixels,
                      fit: BoxFit.cover,
                      cacheWidth: 1200,
                      gaplessPlayback: false,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.black26,
                        ),
                      ),
                    );
                  },
                ),
              if (text.isNotEmpty)
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    text,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: (width / 960 * 19).clamp(8.0, 24.0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final request = widget.launch;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (request.bytes != null) {
          action(() async {
            await load(request.bytes!, name: request.name);
            await rememberCurrent();
          });
        } else if (request.create) {
          create();
        }
      });
    }
  }

  Future<void> rememberCurrent() async {
    final bytes = data;
    if (bytes == null || widget.onRemember == null) return;
    try {
      await widget.onRemember!(bytes, filename);
    } catch (_) {
      message(
        'Рабочая копия не добавлена в историю. Файл можно сохранить через «Сохранить копию».',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = engine != null;
    final compact = MediaQuery.sizeOf(context).height < 650;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return UnsavedChangesGuard(
      dirty: modified,
      busy: busy,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: (MediaQuery.textScalerOf(context).scale(31) + 12)
              .clamp(72.0, 144.0)
              .toDouble(),
          title: EditorFileTitle(
            filename: filename,
            status: enabled ? 'DeckCraft Rust · PPTX' : 'Rust недоступен',
            color: const Color(0xffcc6243),
          ),
          bottom: keyboardOpen
              ? null
              : EditorSectionTabs(
                  color: const Color(0xffcc6243),
                  height: (MediaQuery.textScalerOf(context).scale(16) + 30)
                      .clamp(56.0, 90.0),
                  sections: [
                    EditorToolSection('Главная', commands),
                    EditorToolSection('Вставка', commands),
                    EditorToolSection('Файл', [
                      EditorCommand(
                        'Открыть PPTX',
                        Icons.folder_open,
                        enabled && !busy ? open : null,
                      ),
                      commands.last,
                    ]),
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
            ? EditorWelcome(
                icon: Icons.slideshow_outlined,
                title: 'Презентации',
                openLabel: 'Открыть PPTX',
                createLabel: 'Создать PPTX',
                onOpen: open,
                onCreate: create,
                busy: busy,
              )
            : Column(
                children: [
                  if (!compact)
                    const FormatLimitsNotice(
                      summary: 'PPTX · упрощённый предпросмотр',
                      details:
                          'Встроенные PNG/JPEG/WebP и простые фигуры '
                          'отображаются; темы, сложные эффекты, группы и '
                          'анимации пока поддерживаются не полностью. '
                          'Нажмите текст на слайде для редактирования.',
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
                          child: InteractiveViewer(
                            minScale: .6,
                            maxScale: 4,
                            child: slideCanvas(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!compact)
                    Container(
                      height: 112,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: slides.length,
                        itemBuilder: (c, i) {
                          final selected = i == index;
                          return GestureDetector(
                            onTap: busy
                                ? null
                                : () => setState(() => index = i),
                            child: Container(
                              width: 138,
                              margin: const EdgeInsets.all(5),
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected
                                      ? Colors.deepOrange
                                      : Colors.grey,
                                  width: selected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                      ),
                                      alignment: Alignment.center,
                                      clipBehavior: Clip.hardEdge,
                                      child: IgnorePointer(
                                        child: slideCanvas(slideIndex: i),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    (i + 1).toString(),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  EditorCommandBar(
                    commands: commands,
                    color: const Color(0xffcc6243),
                  ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
      ),
    );
  }
}
