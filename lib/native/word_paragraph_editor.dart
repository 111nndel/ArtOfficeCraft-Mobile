import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showWordParagraphEditor(
  BuildContext context, {
  required Map<String, dynamic> block,
  bool insert = false,
}) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ParagraphEditor(block: block, insert: insert),
);

class _ParagraphEditor extends StatefulWidget {
  const _ParagraphEditor({required this.block, required this.insert});
  final Map<String, dynamic> block;
  final bool insert;
  @override
  State<_ParagraphEditor> createState() => _ParagraphEditorState();
}

class _ParagraphEditorState extends State<_ParagraphEditor> {
  late final TextEditingController text = TextEditingController(
    text: widget.block['text']?.toString() ?? '',
  );
  final Map<String, dynamic> char = {}, para = {};
  @override
  void initState() {
    super.initState();
    text.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    text.removeListener(refresh);
    text.dispose();
    super.dispose();
  }

  bool get dirty =>
      text.text != (widget.block['text'] ?? '') ||
      char.isNotEmpty ||
      para.isNotEmpty;
  bool active(String key) {
    if (char[key] is bool) return char[key] as bool;
    final runs = widget.block['runs'];
    return runs is List && runs.isNotEmpty && (runs.first as Map)[key] == true;
  }

  void apply() {
    if (!dirty || (widget.insert && text.text.trim().isEmpty)) return;
    final selection = text.selection;
    final selected = selection.isValid && !selection.isCollapsed;
    Navigator.pop(context, <String, dynamic>{
      'text': text.text,
      if (!widget.insert && char.isNotEmpty) 'char': char,
      if (!widget.insert && char.isNotEmpty)
        'start': selected ? selection.start : 0,
      if (!widget.insert && char.isNotEmpty)
        'end': selected ? selection.end : text.text.length,
      ...para,
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height - keyboard - 60).clamp(
            100.0,
            1000.0,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.insert ? 'Новый абзац' : 'Редактировать абзац',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('word-paragraph-input'),
                controller: text,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Текст абзаца',
                  alignLabelWithHint: true,
                ),
              ),
              if (!widget.insert) ...[
                const SizedBox(height: 14),
                Text(
                  text.selection.isValid && !text.selection.isCollapsed
                      ? 'Форматирование выделенного текста'
                      : 'Нет выделения — форматирование всего абзаца',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final item in [
                      ('bold', 'Жирный', 'Ж'),
                      ('italic', 'Курсив', 'К'),
                      ('underline', 'Подчеркнуть', 'Ч'),
                    ])
                      Tooltip(
                        message: item.$2,
                        child: FilterChip(
                          selected: active(item.$1),
                          label: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              item.$3,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          onSelected: (value) =>
                              setState(() => char[item.$1] = value),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<double>(
                  isExpanded: true,
                  initialValue: null,
                  decoration: const InputDecoration(
                    labelText: 'Размер шрифта, pt',
                  ),
                  items: [10.0, 12.0, 14.0, 16.0, 18.0, 24.0, 32.0]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(n.toInt().toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => char['size'] = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: widget.block['align']?.toString() ?? 'justify',
                  decoration: const InputDecoration(
                    labelText: 'Выравнивание абзаца',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'left', child: Text('Слева')),
                    DropdownMenuItem(value: 'center', child: Text('По центру')),
                    DropdownMenuItem(value: 'right', child: Text('Справа')),
                    DropdownMenuItem(
                      value: 'justify',
                      child: Text('По ширине'),
                    ),
                    DropdownMenuItem(
                      value: 'distribute',
                      child: Text('Распределённое (исходное)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null && value != 'distribute') {
                      setState(() => para['align'] = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<double>(
                  isExpanded: true,
                  initialValue: null,
                  decoration: const InputDecoration(
                    labelText: 'Межстрочный интервал',
                  ),
                  items: [1.0, 1.15, 1.5, 2.0]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(n.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => para['lineSpacing'] = value);
                    }
                  },
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  FilledButton.icon(
                    onPressed: dirty ? apply : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Применить к документу'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
