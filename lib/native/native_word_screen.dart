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

  final findText = TextEditingController(),
      replaceText = TextEditingController();
  static const _documentCenter = ValueKey('word-document-center');
  int _anchorBlock = 0, _scrollRevision = 0;
  int findCursor = -1;
  List<({int block, int start, int end, bool editable})> get findMatches {
    final query = findText.text;
    final found = <({int block, int start, int end, bool editable})>[];
    if (query.isEmpty) return found;
    for (final block in blocks) {
      final id = block['block'] as int;
      final text = activeBlock == id && inlineDirty
          ? inline.text
          : block['text']?.toString() ?? '';
      var at = 0;
      while ((at = text.indexOf(query, at)) >= 0) {
        found.add((
          block: id,
          start: at,
          end: at + query.length,
          editable: block['editable'] == true,
        ));
        if (found.length >= 10000) return found;
        at += query.length;
      }
    }
    return found;
  }

  Future<void> findNext(int direction) => guarded(() async {
    final matches = findMatches;
    if (matches.isEmpty) return;
    findCursor = findCursor < 0
        ? (direction > 0 ? 0 : matches.length - 1)
        : (findCursor + direction) % matches.length;
    final match = matches[findCursor];
    final block = blocks.firstWhere((b) => b['block'] == match.block);
    if (match.editable) {
      startInline(block, focus: false);
      inline.selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
    } else {
      setState(() => selectedBlock = match.block);
    }
    revealBlock(match.block);
  });

  Future<void> replaceFound(bool all) => guarded(() async {
    if (document == null) return;
    final matches = findMatches;
    if (matches.isEmpty) return;
    final match = matches[(findCursor < 0 ? 0 : findCursor) % matches.length];
    if ((!all && !match.editable) || (all && matches.any((m) => !m.editable))) {
      inform('Некоторые совпадения защищены от редактирования');
      return;
    }
    final previous = document!;
    final replacement = replaceText.text;
    final result = await engine!.editAndInspect(previous, {
      'action': all ? 'replace_all' : 'replace_one',
      'find': findText.text,
      'replacement': replacement,
      if (!all) ...{
        'block': match.block,
        'start': match.start,
        'end': match.end,
      },
    });
    await updatePreview(result.bytes, preview: result.preview);
    if (!mounted) return;
    history.push(previous);
    final after = findMatches;
    final next = after.indexWhere(
      (m) =>
          m.block > match.block ||
          m.block == match.block && m.start >= match.start + replacement.length,
    );
    setState(() {
      changed = true;
      findCursor = all || next < 0 ? -1 : next;
    });
    inform(
      '${tr(context, 'Заменено совпадений')}: ${all ? matches.length : 1}',
    );
  });

  Widget searchPanel() {
    final matches = findMatches;
    final enabled = !busy && !operationPending && matches.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('word-find-input'),
          controller: findText,
          maxLength: 256,
          decoration: InputDecoration(labelText: tr(context, 'Найти текст')),
          onChanged: (_) => setState(() => findCursor = -1),
          onSubmitted: (_) {
            if (!busy) findNext(1);
          },
        ),
        Text(tr(context, 'Точное совпадение с учётом регистра')),
        if (tables > 0)
          const UiText('Содержимое таблиц пока не участвует в поиске'),
        Text('${tr(context, 'Совпадений')}: ${matches.length}'),
        if (matches.length >= 10000)
          const UiText('Слишком много совпадений — уточните запрос'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? () => findNext(-1) : null,
              icon: const Icon(Icons.arrow_upward),
              label: const UiText('Предыдущее совпадение'),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? () => findNext(1) : null,
              icon: const Icon(Icons.arrow_downward),
              label: const UiText('Следующее совпадение'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('word-replace-input'),
          controller: replaceText,
          maxLength: 1024,
          decoration: InputDecoration(labelText: tr(context, 'Заменить на')),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: enabled ? () => replaceFound(false) : null,
              child: const UiText('Заменить совпадение'),
            ),
            OutlinedButton(
              onPressed: enabled && matches.length < 10000
                  ? () => replaceFound(true)
                  : null,
              child: const UiText('Заменить все'),
            ),
          ],
        ),
      ],
    );
  }

  final toolPanel = GlobalKey<EditorToolPanelState>();
  bool toolsExpanded = false;
  late final DocumentBackend? engine =
      widget.backend ?? NativeDocumentBackend.tryOpen(NativeDocumentKind.word);
  final history = DocumentHistory();
  List<Map<String, dynamic>> blocks = [];
  int? selectedBlock;
  Uint8List? document;
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

  void startInline(Map<String, dynamic> block, {bool focus = true}) {
    inline.load(block);
    setState(() {
      activeBlock = block['block'] as int;
      selectedBlock = activeBlock;
      inlineDirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focus && activeBlock != null) inlineFocus.requestFocus();
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
    findText.dispose();
    replaceText.dispose();
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
    bool newDocument = false,
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
      blocks = (summary['blocks'] as List? ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      if (newDocument || _anchorBlock >= blocks.length) {
        _anchorBlock = 0;
        _scrollRevision++;
      }
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
    await updatePreview(bytes, newDocument: true);
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
    await updatePreview(data, newDocument: true);
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
    revealBlock(blocks.last['block'] as int);
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
            await updatePreview(request.bytes!, newDocument: true);
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
      revealBlock(id as int);
      activeBlock = id;
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
          'Цвет текста': EditorTool(
            'Цвет текста',
            Icons.format_color_text,
            children: [
              EditorTool(
                'Автоматический',
                Icons.format_color_reset,
                onPressed: editing
                    ? () => commitInline(
                        patch: {
                          'char': {'color': null},
                        },
                      )
                    : null,
              ),
              for (final color in [
                ('Чёрный', '#000000'),
                ('Синий', '#3565CA'),
                ('Зелёный', '#147553'),
                ('Красный', '#C64246'),
                ('Фиолетовый', '#7B45A0'),
              ])
                EditorTool(
                  color.$1,
                  Icons.circle,
                  onPressed: editing
                      ? () => commitInline(
                          patch: {
                            'char': {'color': color.$2},
                          },
                        )
                      : null,
                ),
            ],
          ),
          'Отступы': EditorTool(
            'Отступы',
            Icons.format_indent_increase,
            children: [
              for (final value in [0, 12, 24, 36])
                EditorTool(
                  '$value pt',
                  Icons.format_indent_increase,
                  localize: false,
                  onPressed: editing
                      ? () => commitInline(patch: {'indentLeft': value})
                      : null,
                ),
            ],
          ),

          'Найти и заменить': EditorTool(
            'Найти и заменить',
            Icons.find_replace,
            builder: (_) => searchPanel(),
          ),

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

  // Two lazy slivers meet at the requested paragraph. A far search result can
  // be mounted immediately, while earlier paragraphs remain scrollable.
  void revealBlock(int id) {
    final position = blocks.indexWhere((block) => block['block'] == id);
    if (position < 0) return;
    setState(() {
      _anchorBlock = position;
      _scrollRevision++;
    });
  }

  Widget documentViewport() => ColoredBox(
    color: const Color(0xffdce1e8),
    child: CustomScrollView(
      key: ValueKey(('word-document', _scrollRevision)),
      center: _documentCenter,
      slivers: [
        if (_anchorBlock > 0) paragraphSliver(before: true),
        paragraphSliver(before: false),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: ColoredBox(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  Widget paragraphSliver({required bool before}) => SliverPadding(
    key: before ? null : _documentCenter,
    padding: EdgeInsets.fromLTRB(
      14,
      before || _anchorBlock == 0 ? 14 : 0,
      14,
      0,
    ),
    sliver: DecoratedSliver(
      decoration: const BoxDecoration(color: Colors.white),
      sliver: SliverPadding(
        padding: EdgeInsets.fromLTRB(
          26,
          before || _anchorBlock == 0 ? 32 : 0,
          26,
          before ? 0 : 32,
        ),
        sliver: SliverList.builder(
          itemCount: before ? _anchorBlock : blocks.length - _anchorBlock,
          itemBuilder: (_, offset) => paragraph(
            blocks[before ? _anchorBlock - 1 - offset : _anchorBlock + offset],
          ),
        ),
      ),
    ),
  );

  Widget paragraph(Map<String, dynamic> block) {
    final alignment = switch (block['align']) {
      'left' => TextAlign.left,
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.justify,
    };
    final style = TextStyle(
      fontFamily: 'serif',
      color: const Color(0xff27313d),
      fontSize: 17,
      height: ((block['lineSpacing'] as num?)?.toDouble() ?? 1.5)
          .clamp(.5, 8.0)
          .toDouble(),
    );
    final runs = block['runs'] as List? ?? const [];
    final text = block['text']?.toString() ?? '';
    return Padding(
      key: ValueKey(('word-paragraph', block['block'])),
      padding: EdgeInsets.only(
        left:
            ((block['indentLeft'] as num?)?.toDouble() ?? 0).clamp(
              0.0,
              2000.0,
            ) *
            4 /
            3,
        bottom: (block['spaceAfter'] as num?)?.toDouble() ?? 12,
      ),
      child: InkWell(
        onTap: busy || block['editable'] != true
            ? null
            : () => editParagraph(block),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: activeBlock == block['block']
              ? TextField(
                  key: const Key('word-inline-input'),
                  controller: inline,
                  focusNode: inlineFocus,
                  readOnly: busy,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(
                    () => inlineDirty = inline.text != block['text'],
                  ),
                  textAlign: alignment,
                  style: style,
                  decoration: InputDecoration.collapsed(
                    hintText: tr(context, 'Начните писать'),
                  ),
                )
              : Text.rich(
                  TextSpan(
                    text: runs.isEmpty
                        ? (text.isNotEmpty
                              ? text
                              : tr(context, 'Коснитесь, чтобы начать писать'))
                        : null,
                    children: [
                      for (final run in runs)
                        TextSpan(
                          text: run['text']?.toString() ?? '',
                          style: WordInlineController.runStyle(run as Map),
                        ),
                    ],
                  ),
                  textAlign: alignment,
                  style: style,
                ),
        ),
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
                Expanded(child: documentViewport()),
              ],
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
