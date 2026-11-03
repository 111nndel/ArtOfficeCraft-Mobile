import '../ui/editor_tools.dart';
import 'word_inline_controller.dart';
import 'word_paragraph_editor.dart';
import 'document_history.dart';
import 'document_backend.dart';
import '../ui/editor_file_title.dart';
import '../workspace/editor_launch.dart';
import 'format_limits_notice.dart';

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
    this.backend,
  });
  final EditorLaunch? launch;
  final RememberFile? onRemember;
  final DocumentBackend? backend;
  @override
  State<NativeWordScreen> createState() => _NativeWordScreenState();
}

class _NativeWordScreenState extends State<NativeWordScreen> {
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
        final updated = await engine!.edit(previous, {
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
        await updatePreview(updated);
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

  Future<void> formatAdvanced() async {
    if (busy || operationPending || activeBlock == null) return;
    setState(() => operationPending = true);
    try {
      if (!await commitInline() || !mounted) return;
      final block = blocks.firstWhere((b) => b['block'] == activeBlock);
      final request = await showWordParagraphEditor(
        context,
        block: block,
        formatOnly: true,
        initialSelection: inline.selection,
      );
      if (request != null && mounted && await commitInline(patch: request)) {
        inlineFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => operationPending = false);
    }
  }

  List<EditorCommand> get inlineCommands => [
    EditorCommand('Готово', Icons.check, busy ? null : finishInline),
    EditorCommand(
      inline.selection.isCollapsed ? 'Жирный абзац' : 'Жирный',
      Icons.format_bold,
      busy || inline.text.isEmpty ? null : () => formatInline('bold'),
    ),
    EditorCommand(
      inline.selection.isCollapsed ? 'Курсив абзаца' : 'Курсив',
      Icons.format_italic,
      busy || inline.text.isEmpty ? null : () => formatInline('italic'),
    ),
    EditorCommand(
      inline.selection.isCollapsed ? 'Подчеркнуть абзац' : 'Подчеркнуть',
      Icons.format_underlined,
      busy || inline.text.isEmpty ? null : () => formatInline('underline'),
    ),
    EditorCommand(
      'Оформление',
      Icons.format_size,
      busy ? null : formatAdvanced,
    ),
    EditorCommand(
      'По ширине',
      Icons.format_align_justify,
      busy ? null : () => commitInline(patch: {'align': 'justify'}),
    ),
  ];

  @override
  void dispose() {
    inline.removeListener(selectionChanged);
    inline.dispose();
    inlineFocus.dispose();
    super.dispose();
  }

  void inform(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> updatePreview(Uint8List bytes) async {
    final summary = await engine!.inspect(bytes);
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
    }
  }

  Future<void> createNew() => guarded(() async {
    var bytes = await engine!.create(
      widget.launch?.template == true ? 'План проекта' : '',
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
        bytes = await engine!.edit(bytes, {'action': 'append', 'text': text});
      }
    }
    await updatePreview(bytes);
    setState(() {
      filename = widget.launch?.template == true
          ? 'План проекта.docx'
          : 'Новый документ.docx';
      changed = true;
    });
    history.clear();
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
        filename = 'Импортированный.docx';
      }
      changed = false;
    });
    await rememberCurrent();
    history.clear();
    inform('Файл открыт локальным движком WordCraft');
  });

  Future<void> appendParagraph() => guarded(() async {
    if (document == null) return;
    final previous = document!;
    final updated = await engine!.edit(previous, {
      'action': 'append',
      'text': '',
    });
    await updatePreview(updated);
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
    final bytes = undo ? history.undo(document!) : history.redo(document!);
    await updatePreview(bytes);
    setState(() => changed = true);
  });
  List<EditorCommand> get commands => [
    EditorCommand(
      'Новый абзац',
      Icons.add,
      document != null && !busy ? appendParagraph : null,
    ),
    EditorCommand(
      'Изменить текст',
      Icons.edit_outlined,
      !busy && selectedBlock != null
          ? () => editParagraph(
              blocks.firstWhere((b) => b['block'] == selectedBlock),
            )
          : null,
    ),
    EditorCommand(
      'Отменить',
      Icons.undo,
      !busy && (history.canUndo || inlineDirty)
          ? () => restoreHistory(true)
          : null,
    ),
    EditorCommand(
      'Повторить',
      Icons.redo,
      !busy && history.canRedo ? () => restoreHistory(false) : null,
    ),
    EditorCommand(
      'Сохранить копию',
      Icons.save_outlined,
      document != null && !busy ? saveAs : null,
    ),
  ];

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
    await rememberCurrent();
    inform('DOCX сохранён в выбранное место');
  });

  @override
  void initState() {
    super.initState();
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
            await rememberCurrent();
          });
        } else if (request.create) {
          createNew();
        }
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final enabled = engine != null;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return UnsavedChangesGuard(
      dirty: changed || inlineDirty,
      busy: busy || operationPending,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: (MediaQuery.textScalerOf(context).scale(31) + 12)
              .clamp(72.0, 144.0)
              .toDouble(),
          title: EditorFileTitle(
            filename: filename,
            status: enabled
                ? (changed || inlineDirty
                      ? 'DOCX · есть изменения'
                      : 'DOCX · на устройстве')
                : 'Rust недоступен',
            color: const Color(0xff3565ca),
          ),
          bottom: keyboardOpen
              ? null
              : EditorSectionTabs(
                  color: const Color(0xff3565ca),
                  height: (MediaQuery.textScalerOf(context).scale(16) + 30)
                      .clamp(56.0, 90.0),
                  sections: [
                    EditorToolSection('Главная', commands),
                    EditorToolSection('Вставка', [commands.first]),
                    EditorToolSection('Файл', [
                      EditorCommand(
                        'Открыть DOCX',
                        Icons.folder_open,
                        enabled && !busy ? openDocument : null,
                      ),
                      commands.last,
                    ]),
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
              if (!keyboardOpen)
                FormatLimitsNotice(
                  summary: 'DOCX · возможности просмотра',
                  details:
                      'Текстовый предпросмотр: таблицы ($tables), '
                      'изображения и точная вёрстка пока не отображаются. '
                      'Коснитесь абзаца: ввод и выделение работают прямо на странице. '
                      'Абзацы с объектами и исправлениями доступны для чтения.',
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
                                            key: const Key('word-inline-input'),
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
                                                  inline.text != block['text'],
                                            ),
                                            textAlign: switch (block['align']) {
                                              'left' => TextAlign.left,
                                              'center' => TextAlign.center,
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
                                                const InputDecoration.collapsed(
                                                  hintText: 'Начните писать',
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
                                                          run['italic'] == true
                                                          ? FontStyle.italic
                                                          : FontStyle.normal,
                                                      decoration:
                                                          run['underline'] ==
                                                              true
                                                          ? TextDecoration
                                                                .underline
                                                          : TextDecoration.none,
                                                      fontSize:
                                                          ((run['size'] as num?)
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
                                                        : 'Коснитесь, чтобы начать писать',
                                                  ),
                                              ],
                                            ),
                                            textAlign: switch (block['align']) {
                                              'left' => TextAlign.left,
                                              'center' => TextAlign.center,
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
              if (activeBlock != null || !keyboardOpen)
                EditorCommandBar(
                  commands: activeBlock != null ? inlineCommands : commands,
                  color: const Color(0xff3565ca),
                ),
            ],
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
