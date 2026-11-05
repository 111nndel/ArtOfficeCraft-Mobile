import '../workspace/document_picker.dart';
import '../workspace/editor_kind.dart';
import '../l10n/app_strings.dart';
import '../workspace/draft_store.dart';

import 'dart:async';
import 'dart:math' as math;

import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import '../ui/page_reading.dart';
import 'document_backend.dart';
import 'document_history.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';

class NativeDeckScreen extends StatefulWidget {
  const NativeDeckScreen({
    super.key,
    this.launch,
    this.onRemember,
    this.onDocumentChanged,
    this.draft,
    this.backend,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  final VoidCallback? onDocumentChanged;
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
  final stripViewport = GlobalKey<ContinuousPagesState>();
  final slideTransform = TransformationController();
  final reading = ReadingModePreference('deck');
  bool toolsExpanded = false;
  bool objectEditing = false;
  int? selectedObject;
  final objectPreview = ValueNotifier<Rect?>(null);
  Rect? _objectStart;
  Offset _objectDelta = Offset.zero;
  late final DocumentBackend? engine =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.deck);
  final history = DocumentHistory();
  Uint8List? data;
  List<Map<String, dynamic>> slides = [];
  List<Size> slideSizes = [];
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
    Map<String, dynamic>? preview,
  }) async {
    bytes = immutableDocumentBytes(bytes);
    final report = preview ?? await engine!.inspect(bytes);
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
      if (!pageW.isFinite || pageW <= 0) pageW = 960;
      if (!pageH.isFinite || pageH <= 0) pageH = 540;
      slideSizes = List.filled(next.length, Size(pageW, pageH));
      index = selected.clamp(0, next.length - 1);
      modified = changed;
      if (name != null) {
        history.clear();
        filename = name;
        textEdit = null;
        objectEditing = false;
        selectedObject = null;
      }
    });
    slideTransform.value = Matrix4.identity();
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
    widget.onDocumentChanged?.call();
  });
  Future<void> open() => action(() async {
    if (!await discard()) return;
    final path = await pickDocument(EditorKind.slides);
    if (path == null) return;
    final file = File(path);
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Файл больше 64 МБ');
    }
    await load(await file.readAsBytes(), name: importedFilename(path, 'pptx'));
    widget.onDocumentChanged?.call();
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
    final previous = data!, previousIndex = index;
    final update = await engine!.editAndInspect(previous, {
      ...request,
      'text': text,
    });
    await load(
      update.bytes,
      preview: update.preview,
      selected: selected,
      changed: true,
    );
    if (mounted) {
      history.push(previous, position: previousIndex);
      setState(() => textEdit = null);
      toolPanel.currentState?.back();
    }
  }

  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
    deckText.dispose();
    slideTransform.dispose();
    objectPreview.dispose();
    reading.dispose();
    if (widget.backend == null) unawaited(closeDocumentBackend(engine));
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

  void selectSlide(int slide) {
    if (busy || slide == index || slide < 0 || slide >= slides.length) return;
    slideTransform.value = Matrix4.identity();
    setState(() {
      index = slide;
      selectedObject = null;
    });
    queueDraft();
  }

  void toggleObjectEditing() {
    if (busy || objectPreview.value != null) return;
    slideTransform.value = Matrix4.identity();
    setState(() {
      objectEditing = !objectEditing;
      selectedObject = null;
    });
  }

  Rect shapeRect(Map shape) {
    final rect = shape['rect'] as Map;
    double read(String key) => (rect[key] as num?)?.toDouble() ?? 0;
    return Rect.fromLTWH(read('x'), read('y'), read('w'), read('h'));
  }

  void beginObjectDrag(int id, Rect original) {
    if (busy) return;
    setState(() => selectedObject = id);
    _objectStart = original;
    _objectDelta = Offset.zero;
    objectPreview.value = original;
  }

  void updateObjectDrag(
    Offset delta,
    double width,
    double height, {
    bool resize = false,
    bool proportional = false,
  }) {
    final original = _objectStart;
    if (original == null) return;
    _objectDelta += Offset(delta.dx * pageW / width, delta.dy * pageH / height);
    if (!resize) {
      final x = (original.left + _objectDelta.dx).clamp(
        0.0,
        math.max(0.0, pageW - original.width),
      );
      final y = (original.top + _objectDelta.dy).clamp(
        0.0,
        math.max(0.0, pageH - original.height),
      );
      objectPreview.value = Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        original.width,
        original.height,
      );
      return;
    }
    final maxW = math.max(1.0, pageW - original.left);
    final maxH = math.max(1.0, pageH - original.top);
    final minW = math.min(8.0, maxW), minH = math.min(8.0, maxH);
    var w = (original.width + _objectDelta.dx).clamp(minW, maxW);
    var h = (original.height + _objectDelta.dy).clamp(minH, maxH);
    if (proportional) {
      final x = _objectDelta.dx / original.width;
      final y = _objectDelta.dy / original.height;
      final upper = math.min(maxW / original.width, maxH / original.height);
      final lower = math.min(
        upper,
        math.max(minW / original.width, minH / original.height),
      );
      final scale = (1 + (x.abs() > y.abs() ? x : y)).clamp(lower, upper);
      w = original.width * scale;
      h = original.height * scale;
    }
    objectPreview.value = Rect.fromLTWH(original.left, original.top, w, h);
  }

  void cancelObjectDrag() {
    _objectStart = null;
    objectPreview.value = null;
  }

  void finishObjectDrag() {
    final old = _objectStart;
    final next = objectPreview.value;
    final id = selectedObject;
    final slide = index;
    _objectStart = null;
    if (busy || next == null || next == old || id == null || data == null) {
      cancelObjectDrag();
      return;
    }
    action(() async {
      try {
        await applyPendingText();
        if (!mounted) return;
        final previous = data!;
        final updated = await engine!.editAndInspect(previous, {
          'action': 'transform_shape',
          'slide': slide,
          'shape': id,
          'x': next.left,
          'y': next.top,
          'w': next.width,
          'h': next.height,
        });
        await load(
          updated.bytes,
          preview: updated.preview,
          selected: slide,
          changed: true,
        );
        if (mounted) history.push(previous, position: slide);
      } finally {
        if (mounted) cancelObjectDrag();
      }
    });
  }

  Future<void> removeSlide() => action(() async {
    await applyPendingText();
    if (!mounted) return;
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
    final previous = data!, previousIndex = index;
    final update = await engine!.editAndInspect(previous, {
      'action': 'delete_slide',
      'slide': index,
    });
    await load(
      update.bytes,
      preview: update.preview,
      selected: index == 0 ? 0 : index - 1,
      changed: true,
    );
    if (mounted) history.push(previous, position: previousIndex);
    message('Слайд удалён');
  });
  Future<void> moveSlide(int target, {bool toEnd = false}) => action(() async {
    if (data == null || target < 0 || target >= slides.length) return;
    await applyPendingText();
    if (!mounted) return;
    if (toEnd) target = slides.length - 1;
    final previous = data!, previousIndex = index;
    final update = await engine!.editAndInspect(previous, {
      'action': 'move_slide',
      'slide': index,
      'to': target,
    });
    await load(
      update.bytes,
      preview: update.preview,
      selected: target,
      changed: true,
    );
    if (mounted) history.push(previous, position: previousIndex);
  });

  Future<void> applyPendingText() async {
    if (textEdit != null) {
      if (textDraftDirty) {
        final viewing = index;
        await applyTextDraft();
        if (!mounted) return;
        if (textEdit != null) {
          throw const FormatException(
            'Сначала примените или отмените введённый текст.',
          );
        }
        setState(() => index = viewing.clamp(0, slides.length - 1));
      } else {
        setState(() => textEdit = null);
      }
    }
  }

  Future<void> restoreHistory(bool undo) => action(() async {
    if (data == null) return;
    if (textDraftDirty) {
      if (undo) {
        setState(() {
          deckText.text = textInitial;
          textEdit = null;
        });
      }
      return;
    }
    final target = undo ? history.undoTarget : history.redoTarget;
    if (target == null) return;
    final previous = data!, previousIndex = index;
    final position =
        (undo ? history.undoPosition : history.redoPosition) ?? index;
    await load(target, selected: position, changed: true);
    if (!mounted) return;
    if (undo) {
      history.undo(previous, position: previousIndex);
    } else {
      history.redo(previous, position: previousIndex);
    }
    setState(() => textEdit = null);
  });
  Widget slideCanvas({int? slideIndex, bool allowEdit = false}) {
    final slideNumber = slideIndex ?? index;
    final current = slides[slideNumber];
    final raw = current['shapes'];
    final shapes = raw is List
        ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
        : <Map<String, dynamic>>[];
    final interactive = slideIndex == null || allowEdit;
    final editing = interactive && slideNumber == index && objectEditing;
    return AspectRatio(
      aspectRatio: pageW / pageH,
      child: LayoutBuilder(
        builder: (ctx, size) {
          final w = size.maxWidth, h = size.maxHeight;
          Widget surface(Rect? preview) => Container(
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
                      w,
                      h,
                      slide: slideNumber,
                      interactive: interactive,
                      editing: editing,
                      preview: editing && shape['id'] == selectedObject
                          ? preview
                          : null,
                    ),
                if (editing)
                  for (final shape in shapes)
                    if (shape['movable'] == true &&
                        shape['id'] == selectedObject)
                      resizeHandle(shape, preview ?? shapeRect(shape), w, h),
              ],
            ),
          );
          return editing
              ? ValueListenableBuilder<Rect?>(
                  valueListenable: objectPreview,
                  builder: (_, preview, _) => surface(preview),
                )
              : surface(null);
        },
      ),
    );
  }

  Widget resizeHandle(
    Map<String, dynamic> shape,
    Rect rect,
    double w,
    double h,
  ) {
    final id = shape['id'] as int;
    return Positioned(
      left: (rect.right * w / pageW - 22).clamp(0.0, math.max(0.0, w - 44)),
      top: (rect.bottom * h / pageH - 22).clamp(0.0, math.max(0.0, h - 44)),
      width: 44,
      height: 44,
      child: GestureDetector(
        key: const Key('deck-object-resize'),
        behavior: HitTestBehavior.opaque,
        onPanStart: busy ? null : (_) => beginObjectDrag(id, shapeRect(shape)),
        onPanUpdate: busy
            ? null
            : (event) => updateObjectDrag(
                event.delta,
                w,
                h,
                resize: true,
                proportional: shape['kind'] == 'picture',
              ),
        onPanEnd: busy ? null : (_) => finishObjectDrag(),
        onPanCancel: busy ? null : cancelObjectDrag,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const SizedBox.square(dimension: 16),
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
    final backend = engine;
    final future = backend is DocumentImages
        ? (backend as DocumentImages)
              .image(document, slide, mediaId)
              .then<Uint8List?>((bytes) => bytes, onError: (Object _) => null)
        : Future<Uint8List?>.value(null);
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
    required bool editing,
    Rect? preview,
  }) {
    final original = shapeRect(shape), rect = preview ?? original;
    final x = rect.left * width / pageW;
    final y = rect.top * height / pageH;
    final w = rect.width * width / pageW;
    final h = rect.height * height / pageH;
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
    final id = shape['id'];
    final canDrag = editing && !busy && shape['movable'] == true && id is int;
    final picked = editing && id == selectedObject;
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
        key: interactive ? ValueKey('deck-object-$slide-$id') : null,
        behavior: canDrag ? HitTestBehavior.opaque : null,
        onTap: canDrag
            ? () => setState(() => selectedObject = id)
            : interactive && editable && !editing
            ? () {
                selectSlide(slide);
                changeText(shape);
              }
            : null,
        onPanStart: canDrag ? (_) => beginObjectDrag(id, original) : null,
        onPanUpdate: canDrag
            ? (event) => updateObjectDrag(event.delta, width, height)
            : null,
        onPanEnd: canDrag ? (_) => finishObjectDrag() : null,
        onPanCancel: canDrag ? cancelObjectDrag : null,
        child: Container(
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.all(text.isEmpty ? 0 : 4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color:
                  (picked ? Theme.of(context).colorScheme.primary : stroke) ??
                  (editable ? const Color(0xffd4dce5) : Colors.transparent),
              width: picked ? 2 : (stroke == null ? 0.7 : 1.5),
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
    reading.addListener(() => setState(() {}));
    unawaited(reading.load());
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
    undo: !busy && (history.canUndo || textDraftDirty)
        ? () => restoreHistory(true)
        : null,
    redo: !busy && !textDraftDirty && history.canRedo
        ? () => restoreHistory(false)
        : null,
    sections: officeSections(
      'deck',
      leading: {
        'Вид': [
          readingModeTool(reading),
          pageJumpTool(
            label: 'Перейти к слайду',
            fieldLabel: 'Номер слайда',
            current: index,
            count: slides.length,
            onJump: busy
                ? null
                : (target) {
                    selectSlide(target);
                    toolPanel.currentState?.setExpanded(false);
                  },
          ),
        ],
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
        'Масштаб': EditorTool(
          'Масштаб',
          Icons.zoom_in,
          children: [
            EditorTool(
              reading.value == ReadingMode.continuous
                  ? 'По ширине страницы'
                  : 'Весь слайд',
              Icons.fit_screen,
              onPressed: () {
                stripViewport.currentState?.fitWidth();
                slideTransform.value = Matrix4.identity();
              },
            ),
          ],
        ),
        'Порядок слайдов': EditorTool(
          'Порядок слайдов',
          Icons.reorder,
          children: [
            EditorTool(
              'На один слайд выше',
              Icons.arrow_upward,
              onPressed: !busy && index > 0 ? () => moveSlide(index - 1) : null,
            ),
            EditorTool(
              'На один слайд ниже',
              Icons.arrow_downward,
              onPressed: !busy && index + 1 < slides.length
                  ? () => moveSlide(index + 1)
                  : null,
            ),
            EditorTool(
              'В начало',
              Icons.first_page,
              onPressed: !busy && index > 0 ? () => moveSlide(0) : null,
            ),
            EditorTool(
              'В конец',
              Icons.last_page,
              onPressed: !busy && index + 1 < slides.length
                  ? () => moveSlide(slides.length - 1, toEnd: true)
                  : null,
            ),
          ],
        ),

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
                    Expanded(child: readingCanvas()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const key = Key('deck-object-editing');
                          final label = objectEditing
                              ? 'Готово'
                              : 'Правка объектов';
                          final icon = Icon(
                            objectEditing ? Icons.check : Icons.open_with,
                          );
                          final onPressed = busy ? null : toggleObjectEditing;
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          return Row(
                            children: [
                              Expanded(
                                child: UiText(
                                  'Слайд ${index + 1} из ${slides.length}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              if (constraints.maxWidth < 260 * textScale)
                                IconButton(
                                  key: key,
                                  tooltip: tr(context, label),
                                  onPressed: onPressed,
                                  icon: icon,
                                )
                              else
                                TextButton.icon(
                                  key: key,
                                  onPressed: onPressed,
                                  icon: icon,
                                  label: UiText(label),
                                ),
                            ],
                          );
                        },
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
                              onTap: busy ? null : () => selectSlide(i),
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

  Widget readingCanvas() {
    if (!objectEditing && reading.value == ReadingMode.continuous) {
      return ContinuousPages(
        key: stripViewport,
        sizes: slideSizes,
        page: index,
        enabled: !busy,
        onPageChanged: selectSlide,
        pageBuilder: (_, slide) => RepaintBoundary(
          child: slideCanvas(slideIndex: slide, allowEdit: true),
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, box) {
        final viewport = box.biggest;
        final width = math.max(
          1.0,
          math.min(viewport.width - 24, (viewport.height - 24) * pageW / pageH),
        );
        final height = width * pageH / pageW;
        final frame = Rect.fromCenter(
          center: viewport.center(Offset.zero),
          width: width,
          height: height,
        );
        final slide = Center(
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8),
                ],
              ),
              child: slideCanvas(),
            ),
          ),
        );
        if (objectEditing) return IgnorePointer(ignoring: busy, child: slide);
        return IgnorePointer(
          ignoring: busy,
          child: PageTurnGesture(
            key: ValueKey(index),
            axis: reading.value.swipeAxis,
            canTurn: (delta) => canTurnAtEdge(
              slideTransform,
              frame,
              viewport,
              reading.value.swipeAxis,
              delta,
            ),
            onTurn: (delta) => selectSlide(index + delta),
            child: InteractiveViewer(
              key: const Key('deck-viewport'),
              transformationController: slideTransform,
              alignment: Alignment.topLeft,
              minScale: 1,
              maxScale: 4,
              child: slide,
            ),
          ),
        );
      },
    );
  }
}
