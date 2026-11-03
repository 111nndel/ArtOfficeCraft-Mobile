import '../l10n/app_strings.dart';
import '../ui/pdf_viewport.dart';
import '../workspace/draft_store.dart';
import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import 'document_backend.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
    this.draft,
    this.backend,
    this.renderer,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
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
  late final DocumentBackend? engine =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.pdf);
  Uint8List? contents;
  List<Map<String, dynamic>> pages = [];
  String filename = 'Новый документ.pdf';
  int selected = 0;
  bool busy = false, changed = false;
  late final PdfPageRenderer _pageRenderer =
      widget.renderer ?? PdfPageRenderer();
  Future<Uint8List>? _pageImage;
  int? _session;
  final Map<int, Future<Uint8List>> _thumbnailImages = {};

  void selectPage(int page) {
    if (busy || contents == null || page < 0 || page >= pages.length) return;
    setState(() {
      selected = page;
      _pageImage = _pageRenderer.render(_session!, page);
    });
    queueDraft();
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
      tip('PDFCraft: $e');
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
  }) async {
    data = immutableDocumentBytes(data);
    final summary = preview ?? await engine!.inspect(data);
    if (!mounted) return;
    final raw = summary['pages'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Страницы PDF не найдены');
    }
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
      selected = page.clamp(0, pages.length - 1);
      changed = edited;
      _thumbnailImages.clear();
      _pageImage = _pageRenderer.render(newSession, selected);
      if (name != null) filename = name;
    });
    if (previousSession != null) {
      unawaited(_pageRenderer.close(previousSession).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
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
  });
  Future<void> open() => execute(() async {
    if (!await discard()) return;
    final path = await FlutterFileDialog.pickFile();
    if (path == null) return;
    final f = File(path);
    if (await f.length() > 64 * 1024 * 1024) {
      throw const FormatException('Слишком большой PDF (>64 МБ)');
    }
    await load(await f.readAsBytes(), name: importedFilename(path, 'pdf'));
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
  Future<void> edit(String action) => execute(() async {
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
      final updated = await engine!.editAndInspect(contents!, {
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
      await load(
        updated.bytes,
        preview: updated.preview,
        page: next,
        edited: true,
      );
      tip('Структура PDF изменена');
    }
  });

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
    _pageImage = _pageRenderer.render(_session!, page);
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
    onExpandedChanged: (value) => setState(() => toolsExpanded = value),
    sections: officeSections(
      'pdf',
      leading: {
        'Чтение': [
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
        'Страницы': [
          EditorTool(
            'Вставить страницу',
            Icons.note_add_outlined,
            onPressed: busy ? null : () => edit('insert_blank'),
          ),
        ],
      },
      overrides: {
        'Масштаб': EditorTool(
          'Масштаб',
          Icons.zoom_in,
          children: [
            EditorTool(
              'По ширине страницы',
              Icons.width_normal,
              onPressed: () => pdfViewport.currentState?.fitWidth(),
            ),
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
                    Expanded(
                      child: PdfViewport(
                        key: pdfViewport,
                        image: _pageImage,
                        pageWidth:
                            (((pages[selected]['rotation'] as num? ?? 0)
                                                    .toInt() %
                                                180 ==
                                            0
                                        ? pages[selected]['width']
                                        : pages[selected]['height'])
                                    as num)
                                .toDouble(),
                        pageHeight:
                            (((pages[selected]['rotation'] as num? ?? 0)
                                                    .toInt() %
                                                180 ==
                                            0
                                        ? pages[selected]['height']
                                        : pages[selected]['width'])
                                    as num)
                                .toDouble(),
                      ),
                    ),
                    if (showThumbnails && !toolsExpanded)
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
                              'Страница ${selected + 1} из ${pages.length}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
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
}
