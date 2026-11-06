import '../workspace/document_picker.dart';
import '../workspace/editor_kind.dart';
import '../l10n/app_strings.dart';
import '../ui/pdf_viewport.dart';
import '../ui/page_reading.dart';
import 'pdf_ocr_panel.dart';
import 'pdf_outline_panel.dart';
import 'pdf_text_panel.dart';
import '../workspace/draft_store.dart';
import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import 'document_backend.dart';
import 'document_history.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';

import 'pdf_page_renderer.dart';

class NativePdfScreen extends StatefulWidget {
  const NativePdfScreen({
    super.key,
    this.launch,
    this.onRemember,
    this.onDocumentChanged,
    this.draft,
    this.backend,
    this.renderer,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  final VoidCallback? onDocumentChanged;
  final DraftSession? draft;
  final DocumentBackend? backend;
  final PdfPageRenderer? renderer;
  @override
  State<NativePdfScreen> createState() => _NativePdfScreenState();
}

class _NativePdfScreenState extends State<NativePdfScreen> {
  bool restoringDraft = false, draftQueued = false;
  void draftStatusChanged() {
    if (mounted) setState(() {});
  }

  void queueDraft() {
    if (draftQueued || restoringDraft || widget.draft == null) return;
    draftQueued = true;
    scheduleMicrotask(() {
      draftQueued = false;
      final bytes = contents;
      if (!mounted || restoringDraft || bytes == null) return;
      widget.draft!.update(
        bytes: bytes,
        name: filename,
        dirty: changed,
        editor: {'changed': changed, 'page': selected},
      );
    });
  }

  final toolPanel = GlobalKey<EditorToolPanelState>();
  bool toolsExpanded = false, showThumbnails = false;
  final pdfViewport = GlobalKey<PdfViewportState>();
  final stripViewport = GlobalKey<ContinuousPagesState>();
  final reading = ReadingModePreference('pdf');
  late final DocumentBackend? engine =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.pdf);
  final history = DocumentHistory();
  final targetPage = TextEditingController();
  final noteText = TextEditingController();
  final insertionText = TextEditingController();
  int insertionSize = 16;
  ({Uint8List document, String text, int size})? placement;
  Object _viewDocument = Object();
  Uint8List? contents;
  List<Map<String, dynamic>> pages = [];
  List<PdfBookmark> bookmarks = [];
  List<({int page, String text})> notes = [];
  bool outlineLimited = false;
  List<Size> pageSizes = [];
  String filename = 'Новый документ.pdf';
  int selected = 0;
  bool busy = false, changed = false;
  late final PdfPageRenderer _pageRenderer =
      widget.renderer ?? PdfPageRenderer();
  int? _session;
  final Map<int, Future<Uint8List>> _thumbnailImages = {};
  final Map<int, Future<Uint8List>> _pageImages = {};

  void selectPage(int page) {
    if (busy ||
        contents == null ||
        page == selected ||
        page < 0 ||
        page >= pages.length) {
      return;
    }
    setState(() => selected = page);
    queueDraft();
  }

  void jumpToPage(int page) {
    FocusManager.instance.primaryFocus?.unfocus();
    selectPage(page);
    toolPanel.currentState?.setExpanded(false);
  }

  Future<Uint8List> raster(int page) {
    final future =
        _pageImages.remove(page) ?? _pageRenderer.render(_session!, page);
    _pageImages[page] = future;
    if (_pageImages.length > 6) _pageImages.remove(_pageImages.keys.first);
    return future;
  }

  Size pageSize(Map<String, dynamic> page) {
    final width = (page['width'] as num?)?.toDouble() ?? 595;
    final height = (page['height'] as num?)?.toDouble() ?? 842;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return const Size(595, 842);
    }
    return Size(width, height);
  }

  void tip(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: UiText(msg), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> execute(Future<void> Function() task) async {
    if (busy || engine == null) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      tip(switch (e) {
        FormatException(
          message: 'The text does not fit here. Choose another position or a smaller size.',
        ) =>
          'Текст здесь не помещается. Выберите другое место или меньший размер.',
        FormatException(
          message: 'The PDF insertion font does not support all characters in this text',
        ) =>
          'Некоторые символы недоступны в шрифте для вставки PDF.',
        FormatException(
          message: 'This PDF page already contains searchable text',
        ) =>
          'На этой странице уже есть текстовый слой.',
        _ => 'PDFCraft: $e',
      });
    } finally {
      if (mounted) setState(() => busy = false);
      queueDraft();
    }
  }

  Future<void> load(
    Uint8List data, {
    String? name,
    bool edited = false,
    int page = 0,
    Map<String, dynamic>? preview,
    bool retainViewport = false,
  }) async {
    data = immutableDocumentBytes(data);
    final summary = preview ?? await engine!.inspect(data);
    if (!mounted) return;
    final raw = summary['pages'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Страницы PDF не найдены');
    }
    final outline = [
      for (final item in summary['bookmarks'] as List? ?? const [])
        if (item case {
          'title': String title,
          'page': int? target,
          'depth': int depth,
        })
          (title: title, page: target, depth: depth),
    ];
    final comments = [
      for (final item in summary['notes'] as List? ?? const [])
        if (item case {'page': int page, 'text': String text}
            when page >= 0 && page < raw.length)
          (page: page, text: text),
    ];
    final newSession = await _pageRenderer.open(data);
    if (!mounted) {
      await _pageRenderer.close(newSession);
      return;
    }
    final previousSession = _session;
    setState(() {
      _session = newSession;
      contents = data;
      pages = raw.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      bookmarks = outline;
      notes = comments;
      outlineLimited = summary['outlineLimited'] == true;
      final sizes = pages.map(pageSize).toList(growable: false);
      if (!retainViewport || !listEquals(pageSizes, sizes)) {
        pageSizes = sizes;
        _viewDocument = Object();
      }
      selected = page.clamp(0, pages.length - 1);
      changed = edited;
      placement = null;
      _thumbnailImages.clear();
      _pageImages.clear();
      if (name != null) {
        history.clear();
        filename = name;
        noteText.clear();
        insertionText.clear();
      }
    });
    if (previousSession != null) {
      unawaited(_pageRenderer.close(previousSession).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
    targetPage.dispose();
    noteText.dispose();
    insertionText.dispose();
    reading.dispose();
    final previous = _session;
    if (previous != null) {
      unawaited(_pageRenderer.close(previous).catchError((Object _) {}));
    }
    if (widget.backend == null) unawaited(closeDocumentBackend(engine));
    super.dispose();
  }

  Future<bool> discard() async {
    if (!changed) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const UiText('Несохранённые изменения'),
            content: const UiText('Заменить текущий PDF без сохранения копии?'),
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

  Future<void> create() => execute(() async {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    String translated(String value) => strings?.translate(value) ?? value;
    if (!await discard()) return;
    await load(
      await engine!.create(),
      name: translated('Новый документ.pdf'),
      edited: true,
    );
    tip('Создан PDF с одной страницей');
    widget.onDocumentChanged?.call();
  });
  Future<void> open() => execute(() async {
    if (!await discard()) return;
    final path = await pickDocument(EditorKind.pdf);
    if (path == null) return;
    final f = File(path);
    if (await f.length() > 64 * 1024 * 1024) {
      throw const FormatException('Слишком большой PDF (>64 МБ)');
    }
    await load(await f.readAsBytes(), name: importedFilename(path, 'pdf'));
    widget.onDocumentChanged?.call();
    await rememberCurrent();
    tip('Структура PDF прочитана');
  });
  Future<void> save() => execute(() async {
    if (restoringDraft) {
      throw const FormatException(
        'Черновик восстановлен не полностью. Он сохранён на главном экране.',
      );
    }
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
    await rememberCurrent();
    tip('Копия PDF сохранена. Подписи могут стать недействительными.');
  });
  Future<void> edit(
    String action, {
    int? to,
    String? text,
    PdfTextBlock? block,
    ({int page, Offset at, int size})? insertion,
    List<PdfOcrWord>? ocrWords,
  }) => execute(() async {
    if (contents == null) return;
    if (action == 'delete') {
      if (pages.length <= 1) {
        tip('Последнюю страницу удалить нельзя');
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const UiText('Удалить страницу?'),
          content: const UiText(
            'Оригинал PDF не изменяется, сохранение только в новую копию.',
          ),
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
    }
    {
      final previous = contents!, previousPage = selected;
      final operationPage = insertion?.page ?? selected;
      final updated = await engine!.editAndInspect(previous, {
        'action': action,
        'page': operationPage,
        'to': ?to,
        'text': ?text,
        if (block != null) ...{'block': block.id, 'original': block.text},
        if (insertion != null) ...{
          'x': insertion.at.dx,
          'y': insertion.at.dy,
          'size': insertion.size,
        },
        if (ocrWords != null)
          'words': [
            for (final word in ocrWords) {'text': word.text, 'rect': word.rect},
          ],
      });
      var next = action == 'move_to' ? to! : operationPage;
      if (action == 'move_up') next--;
      if (action == 'move_down' ||
          action == 'duplicate' ||
          action == 'insert_blank') {
        next++;
      }
      await load(
        updated.bytes,
        preview: updated.preview,
        page: next,
        edited: true,
        retainViewport: insertion != null || ocrWords != null,
      );
      if (!mounted) return;
      history.push(previous, position: previousPage);
      if (action == 'add_note') {
        noteText.clear();
        tip('Заметка добавлена');
      } else if (action == 'replace_text_block') {
        tip('Текст страницы изменён');
      } else if (insertion != null) {
        insertionText.clear();
        tip('Текст добавлен на страницу');
      } else if (ocrWords != null) {
        tip('Текстовый слой добавлен. Сохраните копию PDF.');
      } else {
        tip('Структура PDF изменена');
      }
    }
  });

  void startPlacement() {
    final document = contents;
    final text = insertionText.text.trim();
    if (busy || document == null || text.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    FocusManager.instance.primaryFocus?.unfocus();
    toolPanel.currentState?.setExpanded(false);
    setState(() {
      placement = (document: document, text: text, size: insertionSize);
    });
  }

  Future<void> placeText(int page, Offset point) async {
    final draft = placement;
    if (busy || draft == null || !identical(draft.document, contents)) return;
    setState(() => placement = null);
    await edit(
      'insert_text',
      text: draft.text,
      insertion: (page: page, at: point, size: draft.size),
    );
    if (mounted && identical(draft.document, contents)) {
      toolPanel.currentState?.setExpanded(true);
    }
  }

  Widget insertTextPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('pdf-insert-text-input'),
        controller: insertionText,
        readOnly: busy,
        minLines: 2,
        maxLines: 4,
        maxLength: 1000,
        decoration: InputDecoration(labelText: tr(context, 'Новый текст PDF')),
      ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const UiText('Размер шрифта, pt'),
          DropdownButton<int>(
            value: insertionSize,
            items: [
              for (final size in [12, 16, 20, 24, 32])
                DropdownMenuItem(value: size, child: Text('$size')),
            ],
            onChanged: busy
                ? null
                : (size) => setState(() => insertionSize = size!),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: insertionText,
            builder: (_, value, _) => FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy || value.text.trim().isEmpty
                  ? null
                  : startPlacement,
              child: const UiText('Выбрать место'),
            ),
          ),
        ],
      ),
    ],
  );

  Future<void> restoreHistory(bool undo) => execute(() async {
    final target = undo ? history.undoTarget : history.redoTarget;
    if (target == null || contents == null) return;
    final previous = contents!, previousPage = selected;
    final page =
        (undo ? history.undoPosition : history.redoPosition) ?? selected;
    await load(target, page: page, edited: true);
    if (!mounted) return;
    if (undo) {
      history.undo(previous, position: previousPage);
    } else {
      history.redo(previous, position: previousPage);
    }
  });

  void moveToPage() {
    final page = int.tryParse(targetPage.text.trim());
    if (page == null || page < 1 || page > pages.length) {
      tip('Введите существующий номер страницы');
      return;
    }
    edit('move_to', to: page - 1);
  }

  Widget addNotePanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      UiText('Заметка на странице ${selected + 1}'),
      const SizedBox(height: 8),
      TextField(
        key: const Key('pdf-note-text'),
        controller: noteText,
        readOnly: busy,
        minLines: 2,
        maxLines: 4,
        maxLength: 1000,
        decoration: InputDecoration(labelText: tr(context, 'Текст заметки')),
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: noteText,
        builder: (_, value, _) => FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: busy || value.text.trim().isEmpty
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  edit('add_note', text: value.text);
                },
          icon: const Icon(Icons.add_comment_outlined),
          label: const UiText('Добавить заметку'),
        ),
      ),
    ],
  );

  Widget notesPanel() => notes.isEmpty
      ? const UiText('В этом PDF нет текстовых заметок')
      : SizedBox(
          height: (notes.length * 88.0).clamp(88.0, 248.0),
          child: ListView.builder(
            primary: false,
            itemCount: notes.length,
            itemBuilder: (_, index) {
              final note = notes[index];
              return ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: UiText('Страница ${note.page + 1}'),
                subtitle: Text(note.text),
                onTap: busy ? null : () => jumpToPage(note.page),
              );
            },
          ),
        );

  Widget pageTextPanel() {
    final backend = engine;
    final document = contents;
    final page = selected;
    if (backend is! PdfTextDocuments || document == null) {
      return const UiText('Правка текста PDF недоступна');
    }
    return PdfTextPanel(
      key: ValueKey((document, page)),
      busy: busy,
      load: () => (backend as PdfTextDocuments).pdfTextBlocks(document, page),
      onApply: (block, text) async {
        if (!identical(contents, document) || selected != page) return;
        await edit('replace_text_block', block: block, text: text);
      },
    );
  }

  Widget ocrPanel() {
    final session = _session;
    final page = selected;
    return PdfOcrPanel(
      key: ValueKey((session, page)),
      recognize: busy || session == null
          ? null
          : () => _pageRenderer.recognize(session, page),
      addLayer: busy || session == null
          ? null
          : (words) {
              if (session != _session || page != selected) return;
              edit('add_ocr_layer', ocrWords: words);
            },
    );
  }

  Future<Uint8List> thumbnailFor(int index) {
    final old = _thumbnailImages[index];
    if (old != null) return old;
    if (_thumbnailImages.length >= 24) _thumbnailImages.clear();
    final future = _pageRenderer.render(_session!, index, width: 160);
    _thumbnailImages[index] = future;
    return future;
  }

  Widget pageThumb(int i) {
    final p = pages[i];
    return GestureDetector(
      onTap: () => selectPage(i),
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
                child: FutureBuilder<Uint8List>(
                  future: thumbnailFor(i),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasData) {
                      return Image.memory(snapshot.data!, fit: BoxFit.contain);
                    }
                    if (snapshot.hasError) {
                      return UiText(
                        (i + 1).toString(),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 24,
                        ),
                      );
                    }
                    return const SizedBox(
                      height: 15,
                      width: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  },
                ),
              ),
            ),
            UiText(
              'Стр. ${i + 1} · ${p['rotation']}°',
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
            ),
          ],
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
    final request = widget.launch;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (request.bytes != null) {
          execute(() async {
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
    final page = state['page'] as int;
    if (page < 0 || page >= pages.length) {
      throw const FormatException(
        'Страница черновика не найдена. Черновик сохранён.',
      );
    }
    changed = state['changed'] == true;
    selected = page;
    restoringDraft = false;
    setState(() {});
    queueDraft();
  }

  Future<void> rememberCurrent() async {
    final bytes = contents;
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
    color: const Color(0xffc94e59),
    onExpandedChanged: (value) => setState(() {
      toolsExpanded = value;
      if (value) placement = null;
    }),
    undo: !busy && history.canUndo ? () => restoreHistory(true) : null,
    redo: !busy && history.canRedo ? () => restoreHistory(false) : null,
    sections: officeSections(
      'pdf',
      leading: {
        'Чтение': [
          pageJumpTool(
            label: 'Перейти к странице',
            fieldLabel: 'Номер страницы',
            current: selected,
            count: pages.length,
            onJump: busy ? null : jumpToPage,
          ),
          EditorTool(
            'Предыдущая',
            Icons.chevron_left,
            onPressed: selected > 0 && !busy
                ? () => selectPage(selected - 1)
                : null,
          ),
          EditorTool(
            'Следующая',
            Icons.chevron_right,
            onPressed: selected + 1 < pages.length && !busy
                ? () => selectPage(selected + 1)
                : null,
          ),
        ],
        'Изменить': [
          EditorTool(
            'Вставить текст',
            Icons.add_box_outlined,
            builder: (_) => insertTextPanel(),
          ),
        ],
        'Страницы': [
          EditorTool(
            'Вставить страницу',
            Icons.note_add_outlined,
            onPressed: busy ? null : () => edit('insert_blank'),
          ),
        ],
      },
      overrides: {
        'Режим чтения': readingModeTool(reading),
        'Скан и OCR': EditorTool(
          'Скан и OCR',
          Icons.document_scanner_outlined,
          builder: (_) => ocrPanel(),
        ),
        'Текст PDF': EditorTool(
          'Текст PDF',
          Icons.text_fields,
          builder: (_) => pageTextPanel(),
        ),
        'Комментарий': EditorTool(
          'Комментарий',
          Icons.add_comment_outlined,
          builder: (_) => addNotePanel(),
        ),
        'Все комментарии': EditorTool(
          'Все комментарии',
          Icons.comment_outlined,
          builder: (_) => notesPanel(),
        ),
        'Оглавление': EditorTool(
          'Оглавление',
          Icons.list_alt_outlined,
          builder: (_) => PdfOutlinePanel(
            key: ObjectKey(contents),
            entries: bookmarks,
            limited: outlineLimited,
            onJump: busy ? null : jumpToPage,
          ),
        ),
        'Порядок страниц': EditorTool(
          'Порядок страниц',
          Icons.reorder,
          children: [
            EditorTool(
              'На одну страницу выше',
              Icons.arrow_upward,
              onPressed: !busy && selected > 0 ? () => edit('move_up') : null,
            ),
            EditorTool(
              'На одну страницу ниже',
              Icons.arrow_downward,
              onPressed: !busy && selected + 1 < pages.length
                  ? () => edit('move_down')
                  : null,
            ),
            EditorTool(
              'Переместить к номеру',
              Icons.my_location,
              builder: (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('pdf-target-page'),
                    controller: targetPage,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Номер страницы'),
                    ),
                    onSubmitted: (_) {
                      if (!busy) moveToPage();
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : moveToPage,
                    icon: const Icon(Icons.swap_vert),
                    label: const UiText('Переместить страницу'),
                  ),
                ],
              ),
            ),
          ],
        ),

        'Масштаб': EditorTool(
          'Масштаб',
          Icons.zoom_in,
          children: [
            EditorTool(
              'По ширине страницы',
              Icons.width_normal,
              onPressed: () {
                stripViewport.currentState?.fitWidth();
                pdfViewport.currentState?.fitWidth();
              },
            ),
            if (reading.value != ReadingMode.continuous)
              EditorTool(
                'Вся страница',
                Icons.fit_screen,
                onPressed: () => pdfViewport.currentState?.fitPage(),
              ),
          ],
        ),
        'Повернуть': EditorTool(
          'Повернуть',
          Icons.rotate_right,
          children: [
            EditorTool(
              'Повернуть влево',
              Icons.rotate_left,
              onPressed: busy ? null : () => edit('rotate_ccw'),
            ),
            EditorTool(
              'Повернуть вправо',
              Icons.rotate_right,
              onPressed: busy ? null : () => edit('rotate_cw'),
            ),
          ],
        ),
        'Дублировать': EditorTool(
          'Дублировать',
          Icons.copy,
          onPressed: busy ? null : () => edit('duplicate'),
        ),
        'Удалить': EditorTool(
          'Удалить',
          Icons.delete_outline,
          onPressed: pages.length > 1 && !busy ? () => edit('delete') : null,
        ),
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final available = engine != null;
    return UnsavedChangesGuard(
      interceptBack: toolsExpanded,
      onInterceptBack: () => toolPanel.currentState?.handleBack(),
      onDiscard: widget.draft?.discard,
      dirty: changed,
      busy: busy,
      child: Scaffold(
        bottomNavigationBar: contents != null
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
                  status: available
                      ? (changed
                            ? 'PDF · есть изменения${tr(context, widget.draft?.status ?? '')}'
                            : 'PDF · на устройстве')
                      : 'Rust недоступен',
                  color: const Color(0xffc94e59),
                ),
                actions: [
                  EditorFileMenu(
                    commands: [
                      EditorCommand(
                        'Открыть PDF',
                        Icons.folder_open_outlined,
                        available && !busy ? open : null,
                      ),
                      EditorCommand(
                        'Сохранить PDF',
                        Icons.save_outlined,
                        contents != null && !busy ? save : null,
                      ),
                      EditorCommand(
                        'Новый файл',
                        Icons.note_add_outlined,
                        available && !busy ? create : null,
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          bottom: false,
          child: !available
              ? const Center(child: UiText('PDFCraft Rust недоступен'))
              : contents == null
              ? EditorWelcome(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'PDF',
                  openLabel: 'Открыть PDF',
                  createLabel: 'Новый PDF',
                  onOpen: open,
                  onCreate: create,
                  busy: busy,
                )
              : Column(
                  children: [
                    Expanded(child: pageCanvas()),
                    if (showThumbnails && !toolsExpanded && placement == null)
                      SizedBox(
                        height: 136,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: pages.length,
                          itemBuilder: (c, i) => pageThumb(i),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: UiText(
                              placement != null
                                  ? 'Коснитесь страницы, чтобы вставить текст'
                                  : 'Страница ${selected + 1} из ${pages.length}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (placement != null)
                            IconButton(
                              tooltip: tr(context, 'Отмена'),
                              onPressed: () =>
                                  toolPanel.currentState?.setExpanded(true),
                              icon: const Icon(Icons.close),
                            )
                          else
                            IconButton(
                              tooltip: tr(context, 'Миниатюры страниц'),
                              isSelected: showThumbnails,
                              onPressed: () => setState(
                                () => showThumbnails = !showThumbnails,
                              ),
                              icon: const Icon(Icons.view_carousel_outlined),
                            ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget pageCanvas() {
    if (reading.value == ReadingMode.continuous) {
      return ContinuousPages(
        key: stripViewport,
        sizes: pageSizes,
        page: selected,
        enabled: !busy,
        onPageChanged: selectPage,
        pageBuilder: (_, page) => _PdfStripPage(
          key: ValueKey((_session, page)),
          render: () => raster(page),
          onPageTap: placement == null
              ? null
              : (point) => placeText(page, point),
        ),
      );
    }
    final page = selected;
    return IgnorePointer(
      ignoring: busy,
      child: PdfViewport(
        key: pdfViewport,
        image: raster(page),
        pageWidth: pageSizes[page].width,
        pageHeight: pageSizes[page].height,
        pageIdentity: (_viewDocument, page),
        turnAxis: reading.value.swipeAxis,
        onTurn: (delta) => selectPage(selected + delta),
        onPageTap: placement == null ? null : (point) => placeText(page, point),
      ),
    );
  }
}

class _PdfStripPage extends StatefulWidget {
  const _PdfStripPage({super.key, required this.render, this.onPageTap});

  final Future<Uint8List> Function() render;
  final ValueChanged<Offset>? onPageTap;

  @override
  State<_PdfStripPage> createState() => _PdfStripPageState();
}

class _PdfStripPageState extends State<_PdfStripPage> {
  late final image = widget.render();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: PdfPageImage(
      image: image,
      fit: BoxFit.contain,
      onPageTap: widget.onPageTap,
    ),
  );
}
