import '../workspace/document_picker.dart';
import '../workspace/editor_kind.dart';
import '../l10n/app_strings.dart';
import '../workspace/draft_store.dart';

import 'dart:async';

import '../ui/office_tool_sections.dart';
import '../ui/editor_tools.dart';
import 'word_inline_controller.dart';
import 'document_history.dart';
import 'document_backend.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'imported_filename.dart';
import 'unsaved_changes_guard.dart';

/// Real DOCX read/append/save path, not a full Word layout renderer.
class NativeWordScreen extends StatefulWidget {
  const NativeWordScreen({
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
  State<NativeWordScreen> createState() => _NativeWordScreenState();
}

class _NativeWordScreenState extends State<NativeWordScreen> {
  bool restoringDraft = false, draftQueued = false;
  void draftStatusChanged() {
    if (mounted) setState(() {});
  }

  void queueDraft() {
    if (draftQueued || restoringDraft || widget.draft == null) return;
    draftQueued = true;
    scheduleMicrotask(() {
      draftQueued = false;
      final bytes = document;
      if (!mounted || restoringDraft || bytes == null) return;
      widget.draft!.update(
        bytes: bytes,
        name: filename,
        dirty: changed || inlineDirty,
        editor: {
          'changed': changed,
          'activeBlock': activeBlock,
          'text': inline.text,
          'baseOffset': inline.selection.baseOffset,
          'extentOffset': inline.selection.extentOffset,
        },
      );
    });
  }

  final toolPanel = GlobalKey<EditorToolPanelState>();
  bool toolsExpanded = false;
  late final DocumentBackend? engine =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.word);
  final history = DocumentHistory();
  List<Map<String, dynamic>> blocks = [];
  int? selectedBlock;
  Uint8List? document;
  List<String> paragraphs = [];
  String filename = 'Документ.docx';
  int tables = 0;
  bool changed = false;
  bool busy = false;
  final inline = WordInlineController();
  final inlineFocus = FocusNode();
  int? activeBlock;
  bool inlineDirty = false;
  bool operationPending = false;

  void selectionChanged() {
    if (mounted) setState(() {});
    queueDraft();
  }

  void startInline(Map<String, dynamic> block) {
    inline.load(block);
    setState(() {
      activeBlock = block['block'] as int;
      selectedBlock = activeBlock;
      inlineDirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && activeBlock != null) inlineFocus.requestFocus();
    });
  }

  Future<bool> commitInline({
    Map<String, dynamic> patch = const {},
    bool finish = false,
  }) async {
    if (activeBlock == null) return true;
    if (busy || document == null) return false;
    final id = activeBlock!;
    if (inlineDirty || patch.isNotEmpty) {
      final previous = document!;
      final selection = inline.selection;
      setState(() => busy = true);
      try {
        final updated = await engine!.editAndInspect(previous, {
          'action': 'paragraph',
          'block': id,
          'text': inline.text,
          if (patch.containsKey('char')) ...{
            'start': selection.isValid && !selection.isCollapsed
                ? selection.start
                : 0,
            'end': selection.isValid && !selection.isCollapsed
                ? selection.end
                : inline.text.length,
          },
          ...patch,
        });
        await updatePreview(updated.bytes, preview: updated.preview);
        if (!mounted) return false;
        history.push(previous);
        inline.load(
          blocks.firstWhere((b) => b['block'] == id),
          selection: selection,
        );
        setState(() {
          changed = true;
          inlineDirty = false;
          selectedBlock = id;
        });
      } catch (error) {
        inform(
          'Не удалось применить изменения. Введённый текст оставлен на экране: $error',
        );
        return false;
      } finally {
        if (mounted) setState(() => busy = false);
        queueDraft();
      }
    }
    if (mounted && finish) {
      inlineFocus.unfocus();
      setState(() {
        activeBlock = null;
        inlineDirty = false;
      });
    }
    return true;
  }

  Future<void> finishInline() async {
    if (operationPending) return;
    await commitInline(finish: true);
  }

  Future<void> formatInline(String property) async {
    if (operationPending) return;
    await commitInline(
      patch: {
        'char': {property: !inline.propertyAtSelection(property)},
      },
    );
  }

  @override
  void dispose() {
    widget.draft?.removeListener(draftStatusChanged);
    if (widget.draft != null) unawaited(widget.draft!.close());
    inline.removeListener(selectionChanged);
    inline.dispose();
    inlineFocus.dispose();
    if (widget.backend == null) unawaited(closeDocumentBackend(engine));
    super.dispose();
  }

  void inform(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: UiText(text), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> updatePreview(
    Uint8List bytes, {
    Map<String, dynamic>? preview,
  }) async {
    bytes = immutableDocumentBytes(bytes);
    final summary = preview ?? await engine!.inspect(bytes);
    if (!mounted) return;
    final lines = summary['paragraphs'];
    if (lines is! List) {
      throw const FormatException('WordCraft не вернул абзацы');
    }
    setState(() {
      document = bytes;
      paragraphs = lines.map((item) => item.toString()).toList();
      blocks = (summary['blocks'] as List? ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      selectedBlock =
          blocks.where((b) => b['editable'] == true).firstOrNull?['block']
              as int?;
      tables = (summary['tables'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> guarded(Future<void> Function() action) async {
    if (busy || operationPending || engine == null) return;
    operationPending = true;
    try {
      if (!await commitInline(finish: true) || !mounted) return;
      setState(() => busy = true);
      await action();
    } catch (error) {
      inform('Операция не выполнена: $error');
    } finally {
      operationPending = false;
      if (mounted) setState(() => busy = false);
      queueDraft();
    }
  }

  Future<bool> confirmReplace() async {
    if (changed && document != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const UiText('Несохранённые изменения'),
          content: const UiText(
            'Продолжить без сохранения текущего документа?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const UiText('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const UiText('Продолжить'),
            ),
          ],
        ),
      );
      if (proceed != true) return false;
    }
    return true;
  }

  Future<void> createNew() => guarded(() async {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    String translated(String value) => strings?.translate(value) ?? value;
    if (!await confirmReplace()) return;
    var bytes = await engine!.create(
      widget.launch?.template == true ? translated('План проекта') : '',
    );
    if (widget.launch?.template == true) {
      for (final text in [
        'Цель проекта',
        'Опишите результат, который хотите получить.',
        'Этапы и сроки',
        '1. Исследование\n2. Проектирование\n3. Проверка',
        'Следующий шаг',
        'Определите ближайшую задачу и ответственного.',
      ]) {
        bytes = await engine!.edit(bytes, {
          'action': 'append',
          'text': translated(text),
        });
      }
    }
    await updatePreview(bytes);
    setState(() {
      filename = widget.launch?.template == true
          ? translated('План проекта.docx')
          : translated('Новый документ.docx');
      changed = true;
    });
    widget.onDocumentChanged?.call();
    history.clear();
  });

  Future<void> openDocument() => guarded(() async {
    if (!await confirmReplace()) return;
    final selected = await pickDocument(EditorKind.word);
    if (selected == null) return;
    final file = File(selected);
    final length = await file.length();
    if (length > 64 * 1024 * 1024) {
      throw const FormatException(
        'Максимальный размер DOCX для этой сборки — 64 МБ',
      );
    }
    final data = await file.readAsBytes();
    await updatePreview(data);
    setState(() {
      filename = importedFilename(selected, 'docx');
      if (!filename.toLowerCase().endsWith('.docx')) {
        filename = tr(context, 'Импортированный.docx');
      }
      changed = false;
    });
    widget.onDocumentChanged?.call();
    await rememberCurrent();
    history.clear();
    inform('Файл открыт локальным движком WordCraft');
  });

  Future<void> appendParagraph() => guarded(() async {
    if (document == null) return;
    final previous = document!;
    final updated = await engine!.editAndInspect(previous, {
      'action': 'append',
      'text': '',
    });
    await updatePreview(updated.bytes, preview: updated.preview);
    if (!mounted) return;
    history.push(previous);
    setState(() => changed = true);
    startInline(blocks.last);
  });

  Future<void> editParagraph(Map<String, dynamic> block) async {
    if (busy ||
        operationPending ||
        block['editable'] != true ||
        activeBlock == block['block']) {
      return;
    }
    final id = block['block'];
    operationPending = true;
    try {
      if (!await commitInline(finish: true) || !mounted) return;
      startInline(blocks.firstWhere((b) => b['block'] == id));
    } finally {
      operationPending = false;
    }
  }

  Future<void> restoreHistory(bool undo) => guarded(() async {
    if (document == null || (undo ? !history.canUndo : !history.canRedo)) {
      return;
    }
    final previous = document!;
    final target = undo ? history.undoTarget : history.redoTarget;
    if (target == null) return;
    await updatePreview(target);
    if (!mounted) return;
    if (undo) {
      history.undo(previous);
    } else {
      history.redo(previous);
    }
    setState(() => changed = true);
  });
  Future<void> saveAs() => guarded(() async {
    if (restoringDraft) {
      throw const FormatException(
        'Черновик восстановлен не полностью. Он сохранён на главном экране.',
      );
    }
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
    await rememberCurrent();
    inform('DOCX сохранён в выбранное место');
  });

  @override
  void initState() {
    super.initState();
    restoringDraft = widget.launch?.recovery != null;
    widget.draft?.addListener(draftStatusChanged);
    inline.addListener(selectionChanged);
    final request = widget.launch;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (request.bytes != null) {
          guarded(() async {
            await updatePreview(request.bytes!);
            setState(() {
              filename = request.name ?? filename;
              changed = false;
            });
            restoreDraft(request.recovery);
            if (request.recovery == null) await rememberCurrent();
          });
        } else if (request.create) {
          createNew();
        }
      });
    }
  }

  void restoreDraft(Map<String, dynamic>? state) {
    if (state == null) return;
    final id = state['activeBlock'];
    if (id != null) {
      final block = blocks
          .where((b) => b['block'] == id && b['editable'] == true)
          .firstOrNull;
      if (block == null) {
        throw const FormatException(
          'Абзац черновика не найден. Черновик оставлен для повторного восстановления.',
        );
      }
      inline.load(block);
      activeBlock = id as int;
      selectedBlock = activeBlock;
      inline.text = state['text'] as String;
      final base = (state['baseOffset'] as int? ?? inline.text.length).clamp(
        0,
        inline.text.length,
      );
      final extent = (state['extentOffset'] as int? ?? base).clamp(
        0,
        inline.text.length,
      );
      inline.selection = TextSelection(baseOffset: base, extentOffset: extent);
      inlineDirty = inline.text != block['text'];
    }
    changed = state['changed'] == true;
    restoringDraft = false;
    setState(() {});
    queueDraft();
  }

  Future<void> rememberCurrent() async {
    final bytes = document;
    if (bytes == null || widget.onRemember == null) return;
    try {
      await widget.onRemember!(bytes, filename);
    } catch (_) {
      inform(
        'Рабочая копия не добавлена в историю. Файл можно сохранить через «Сохранить копию».',
      );
    }
  }

  Widget editorPanel() {
    final editing = activeBlock != null && !busy && !operationPending;
    EditorTool alignment(String name, String value, IconData icon) =>
        EditorTool(
          name,
          icon,
          onPressed: editing
              ? () => commitInline(patch: {'align': value})
              : null,
        );
    return EditorToolPanel(
      key: toolPanel,
      color: const Color(0xff3565ca),
      onExpandedChanged: (value) => setState(() => toolsExpanded = value),
      undo: !busy && (history.canUndo || inlineDirty)
          ? () => restoreHistory(true)
          : null,
      redo: !busy && history.canRedo ? () => restoreHistory(false) : null,
      sections: officeSections(
        'word',
        exclude: {'Шрифт и стиль', 'Ж', 'К', 'Ч'},
        leading: {
          'Главная': [
            EditorTool(
              'Стиль',
              Icons.text_fields,
              inline: true,
              builder: (_) => EditorTextStyleControls(
                bold: editing && inline.propertyAtSelection('bold'),
                italic: editing && inline.propertyAtSelection('italic'),
                underline: editing && inline.propertyAtSelection('underline'),
                onBold: editing ? () => formatInline('bold') : null,
                onItalic: editing ? () => formatInline('italic') : null,
                onUnderline: editing ? () => formatInline('underline') : null,
                onSize: editing
                    ? (v) => commitInline(
                        patch: {
                          'char': {'size': v},
                        },
                      )
                    : null,
              ),
            ),
            EditorTool(
              'Готово',
              Icons.check,
              onPressed: activeBlock == null || busy ? null : finishInline,
            ),
          ],
          'Вставка': [
            EditorTool(
              'Новый абзац',
              Icons.add,
              onPressed: busy ? null : appendParagraph,
            ),
          ],
        },
        overrides: {
          'Абзац': EditorTool(
            'Абзац',
            Icons.format_align_justify,
            children: [
              alignment('Слева', 'left', Icons.format_align_left),
              alignment('По центру', 'center', Icons.format_align_center),
              alignment('Справа', 'right', Icons.format_align_right),
              alignment('По ширине', 'justify', Icons.format_align_justify),
              EditorTool(
                'Межстрочный интервал',
                Icons.format_line_spacing,
                children: [
                  for (final v in [1.0, 1.15, 1.5, 2.0])
                    EditorTool(
                      '$v',
                      Icons.format_line_spacing,
                      onPressed: editing
                          ? () => commitInline(patch: {'lineSpacing': v})
                          : null,
                    ),
                ],
              ),
            ],
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = engine != null;
    return UnsavedChangesGuard(
      interceptBack: toolsExpanded,
      onInterceptBack: () => toolPanel.currentState?.handleBack(),
      onDiscard: widget.draft?.discard,
      dirty: changed || inlineDirty,
      busy: busy || operationPending,
      child: Scaffold(
        bottomNavigationBar: document != null
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
                      ? (changed || inlineDirty
                            ? 'DOCX · есть изменения${tr(context, widget.draft?.status ?? '')}'
                            : 'DOCX · на устройстве')
                      : 'Rust недоступен',
                  color: const Color(0xff3565ca),
                ),
                actions: [
                  EditorFileMenu(
                    commands: [
                      EditorCommand(
                        'Открыть DOCX',
                        Icons.folder_open_outlined,
                        enabled && !busy ? openDocument : null,
                      ),
                      EditorCommand(
                        'Сохранить как DOCX',
                        Icons.save_outlined,
                        document != null && !busy ? saveAs : null,
                      ),
                      EditorCommand(
                        'Новый файл',
                        Icons.note_add_outlined,
                        enabled && !busy ? createNew : null,
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (!enabled)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: UiText(
                    'Нативная библиотека libartoffice_core.so недоступна. '
                    'Для реального DOCX требуется Android ARM64.',
                  ),
                ),
              if (enabled && document == null)
                Expanded(
                  child: EditorWelcome(
                    icon: Icons.description_outlined,
                    title: 'Документы',
                    openLabel: 'Открыть DOCX',
                    createLabel: 'Новый DOCX',
                    onOpen: openDocument,
                    onCreate: createNew,
                    busy: busy,
                  ),
                )
              else if (document != null) ...[
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final block in blocks)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        (block['spaceAfter'] as num?)
                                            ?.toDouble() ??
                                        12,
                                  ),
                                  child: InkWell(
                                    onTap: busy || block['editable'] != true
                                        ? null
                                        : () => editParagraph(block),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 7,
                                      ),
                                      child: activeBlock == block['block']
                                          ? TextField(
                                              key: const Key(
                                                'word-inline-input',
                                              ),
                                              controller: inline,
                                              focusNode: inlineFocus,
                                              readOnly: busy,
                                              minLines: 1,
                                              maxLines: null,
                                              keyboardType:
                                                  TextInputType.multiline,
                                              textCapitalization:
                                                  TextCapitalization.sentences,
                                              onChanged: (_) => setState(
                                                () => inlineDirty =
                                                    inline.text !=
                                                    block['text'],
                                              ),
                                              textAlign:
                                                  switch (block['align']) {
                                                    'left' => TextAlign.left,
                                                    'center' =>
                                                      TextAlign.center,
                                                    'right' => TextAlign.right,
                                                    _ => TextAlign.justify,
                                                  },
                                              style: const TextStyle(
                                                fontFamily: 'serif',
                                                color: Color(0xff27313d),
                                                fontSize: 17,
                                                height: 1.5,
                                              ),
                                              decoration:
                                                  InputDecoration.collapsed(
                                                    hintText: tr(
                                                      context,
                                                      'Начните писать',
                                                    ),
                                                  ),
                                            )
                                          : Text.rich(
                                              TextSpan(
                                                children: [
                                                  for (final run
                                                      in (block['runs']
                                                              as List? ??
                                                          []))
                                                    TextSpan(
                                                      text:
                                                          run['text']
                                                              ?.toString() ??
                                                          '',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            run['bold'] == true
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        fontStyle:
                                                            run['italic'] ==
                                                                true
                                                            ? FontStyle.italic
                                                            : FontStyle.normal,
                                                        decoration:
                                                            run['underline'] ==
                                                                true
                                                            ? TextDecoration
                                                                  .underline
                                                            : TextDecoration
                                                                  .none,
                                                        fontSize:
                                                            ((run['size']
                                                                        as num?)
                                                                    ?.toDouble() ??
                                                                12) *
                                                            1.33,
                                                      ),
                                                    ),
                                                  if ((block['runs'] as List? ??
                                                          [])
                                                      .isEmpty)
                                                    TextSpan(
                                                      text:
                                                          block['text']
                                                                  ?.toString()
                                                                  .isNotEmpty ==
                                                              true
                                                          ? block['text']
                                                                .toString()
                                                          : tr(
                                                              context,
                                                              'Коснитесь, чтобы начать писать',
                                                            ),
                                                    ),
                                                ],
                                              ),
                                              textAlign:
                                                  switch (block['align']) {
                                                    'left' => TextAlign.left,
                                                    'center' =>
                                                      TextAlign.center,
                                                    'right' => TextAlign.right,
                                                    _ => TextAlign.justify,
                                                  },
                                              style: const TextStyle(
                                                fontFamily: 'serif',
                                                color: Color(0xff27313d),
                                                fontSize: 17,
                                                height: 1.5,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
