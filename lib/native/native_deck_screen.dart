import '../l10n/app_strings.dart';
import '../workspace/draft_store.dart';

import 'dart:async';

import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import 'document_backend.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';
import 'deckcraft_bridge.dart';

class NativeDeckScreen extends StatefulWidget {
  const NativeDeckScreen({
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
  State<NativeDeckScreen> createState() => _NativeDeckScreenState();
}

class _NativeDeckScreenState extends State<NativeDeckScreen> {
  bool restoringDraft = false, draftQueued = false;
  void draftStatusChanged() {
    if (mounted) setState(() {});
  }

  void queueDraft() {
    if (draftQueued || restoringDraft || widget.draft == null) return;
    draftQueued = true;
    scheduleMicrotask(() {
      draftQueued = false;
      final bytes = data;
      if (!mounted || restoringDraft || bytes == null) return;
      widget.draft!.update(
        bytes: bytes,
        name: filename,
        dirty: modified || textDraftDirty,
        editor: {
          'modified': modified,
          'slide': index,
          'textEdit': textEdit == null
              ? null
              : Map<String, dynamic>.of(textEdit!),
          'text': deckText.text,
          'initial': textInitial,
          'heading': textHeading,
        },
      );
    });
  }

  final toolPanel = GlobalKey<EditorToolPanelState>();
  bool toolsExpanded = false;
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
        SnackBar(content: UiText(value), duration: const Duration(seconds: 3)),
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
      queueDraft();
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
      if (name != null) {
        filename = name;
        textEdit = null;
      }
    });
  }

  Future<bool> discard() async {
    if (!modified && !textDraftDirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const UiText('Несохранённые изменения'),
            content: const UiText(
              'Открыть другую презентацию без сохранения текущей?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const UiText('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const UiText('Продолжить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> create() => action(() async {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    String translated(String value) => strings?.translate(value) ?? value;
    if (!await discard()) return;
    var bytes = await engine!.create();
    if (widget.launch?.template == true) {
      bytes = await engine!.edit(bytes, {
        'action': 'add_text',
        'slide': 0,
        'text': translated('Идея, которая объединяет.'),
      });
      bytes = await engine!.edit(bytes, {
        'action': 'add_slide',
        'text': translated('От идеи — к действию'),
      });
      bytes = await engine!.edit(bytes, {
        'action': 'add_slide',
        'text': translated('Следующий шаг'),
      });
    }
    await load(
      bytes,
      name: widget.launch?.template == true
          ? translated('Презентация идеи.pptx')
          : translated('Новая презентация.pptx'),
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
    if (restoringDraft) {
      throw const FormatException(
        'Черновик восстановлен не полностью. Он сохранён на главном экране.',
      );
    }
    if (!loaded) return;
    if (textDraftDirty) await applyTextDraft();
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
  final deckText = TextEditingController();
  Map<String, dynamic>? textEdit;
  String textHeading = 'Текст', textInitial = '';
  bool get textDraftDirty => textEdit != null && deckText.text != textInitial;
  void beginText(
    String heading,
    Map<String, dynamic> request, {
    String initial = '',
  }) {
    if (busy) return;
    if (textDraftDirty) {
      message('Сначала примените или отмените введённый текст.');
      toolPanel.currentState?.openTool(0, [0]);
      return;
    }
    setState(() {
      textEdit = request;
      textHeading = heading;
      textInitial = initial;
      deckText.text = initial;
    });
    toolPanel.currentState?.openTool(0, [0]);
  }

  void finishText(bool apply) {
    final request = textEdit;
    if (!apply || request == null) {
      setState(() => textEdit = null);
      toolPanel.currentState?.back();
      queueDraft();
      return;
    }
    action(applyTextDraft);
  }

  Future<void> applyTextDraft() async {
    final request = textEdit;
    if (request == null) return;
    final text = deckText.text;
    if (request['action'] == 'add_text' && text.trim().isEmpty) return;
    final selected = request['action'] == 'add_slide'
        ? slides.length
        : (request['slide'] as int? ?? index);
    await load(
      await engine!.edit(data!, {...request, 'text': text}),
      selected: selected,
      changed: true,
    );
    if (mounted) {
      setState(() => textEdit = null);
      toolPanel.currentState?.back();
    }
  }

  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
    deckText.dispose();
    super.dispose();
  }

  void newSlide() =>
      beginText('Заголовок нового слайда', {'action': 'add_slide'});
  void insertText() =>
      beginText('Новый текстовый блок', {'action': 'add_text', 'slide': index});
  void changeText(Map<String, dynamic> shape) => beginText('Изменить текст', {
    'action': 'edit_text',
    'slide': index,
    'shape': shape['id'],
  }, initial: shape['text']?.toString() ?? '');
  Future<void> removeSlide() => action(() async {
    if (slides.length <= 1) {
      message('Нельзя удалить последний слайд');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const UiText('Удалить слайд?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const UiText('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const UiText('Удалить'),
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
    restoringDraft = widget.launch?.recovery != null;
    widget.draft?.addListener(draftStatusChanged);
    deckText.addListener(() {
      if (mounted) setState(() {});
      queueDraft();
    });
    final request = widget.launch;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (request.bytes != null) {
          action(() async {
            await load(request.bytes!, name: request.name);
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
    final slide = state['slide'] as int;
    if (slide < 0 || slide >= slides.length) {
      throw const FormatException(
        'Слайд черновика не найден. Черновик сохранён.',
      );
    }
    index = slide;
    final edit = state['textEdit'];
    if (edit != null) {
      final request = Map<String, dynamic>.from(edit as Map);
      if (!['add_text', 'add_slide', 'edit_text'].contains(request['action'])) {
        throw const FormatException('Неизвестный текстовый черновик.');
      }
      textEdit = request;
      textInitial = state['initial'] as String;
      deckText.text = state['text'] as String;
      textHeading = state['heading'] as String;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) toolPanel.currentState?.openTool(0, [0]);
      });
    }
    modified = state['modified'] == true;
    restoringDraft = false;
    setState(() {});
    queueDraft();
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

  Widget editorPanel() => EditorToolPanel(
    key: toolPanel,
    color: const Color(0xffcc6243),
    onExpandedChanged: (value) => setState(() => toolsExpanded = value),
    sections: officeSections(
      'deck',
      leading: {
        'Главная': [
          EditorTool(
            'Текст',
            Icons.text_fields,
            builder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UiText(
                  textHeading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('deck-text-input'),
                  controller: deckText,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: tr(context, 'Текст на слайде'),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => finishText(false),
                      child: const UiText('Отмена'),
                    ),
                    FilledButton(
                      onPressed: textEdit != null && !busy
                          ? () => finishText(true)
                          : null,
                      child: const UiText('Применить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          EditorTool(
            'Текстовые объекты',
            Icons.list_alt,
            children: [
              for (final shape
                  in (slides[index]['shapes'] as List? ?? []).where(
                    (x) => x['editableText'] == true,
                  ))
                EditorTool(
                  shape['text']?.toString() ?? tr(context, 'Текст'),
                  localize: false,
                  Icons.text_fields,
                  onPressed: busy
                      ? null
                      : () =>
                            changeText(Map<String, dynamic>.from(shape as Map)),
                ),
            ],
          ),
          EditorTool(
            'Удалить слайд',
            Icons.delete_outline,
            onPressed: !busy && slides.length > 1 ? removeSlide : null,
          ),
        ],
      },
      exclude: {'Текст'},
      overrides: {
        'Новый слайд': EditorTool(
          'Новый слайд',
          Icons.add,
          onPressed: busy ? null : newSlide,
        ),
        'Текстовый блок': EditorTool(
          'Текстовый блок',
          Icons.text_fields,
          onPressed: busy ? null : insertText,
        ),
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = engine != null;
    final compact = MediaQuery.sizeOf(context).height < 650;
    return UnsavedChangesGuard(
      interceptBack: toolsExpanded,
      onInterceptBack: () => toolPanel.currentState?.handleBack(),
      onDiscard: widget.draft?.discard,
      dirty: modified || textDraftDirty,
      busy: busy,
      child: Scaffold(
        bottomNavigationBar: loaded
            ? Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: editorPanel(),
              )
            : null,
        appBar: toolsExpanded
            ? null
            : AppBar(
                toolbarHeight: (MediaQuery.textScalerOf(context).scale(31) + 12)
                    .clamp(72.0, 144.0)
                    .toDouble(),
                title: EditorFileTitle(
                  filename: filename,
                  status: enabled
                      ? (modified
                            ? 'PPTX · есть изменения${tr(context, widget.draft?.status ?? '')}'
                            : 'PPTX · на устройстве')
                      : 'Rust недоступен',
                  color: const Color(0xffcc6243),
                ),
                actions: [
                  EditorFileMenu(
                    commands: [
                      EditorCommand(
                        'Открыть PPTX',
                        Icons.folder_open_outlined,
                        enabled && !busy ? open : null,
                      ),
                      EditorCommand(
                        'Сохранить копию PPTX',
                        Icons.save_outlined,
                        loaded && !busy ? save : null,
                      ),
                      EditorCommand(
                        'Новый файл',
                        Icons.note_add_outlined,
                        enabled && !busy ? create : null,
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          bottom: false,
          child: !enabled
              ? const Center(
                  child: UiText('DeckCraft Rust недоступен на этом устройстве'),
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
                    if (!compact && !toolsExpanded)
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
                                    UiText(
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
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }
}
