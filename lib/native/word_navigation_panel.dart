import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'word_document_index.dart';

class WordNavigationPanel extends StatefulWidget {
  const WordNavigationPanel({
    super.key,
    required this.index,
    required this.enabled,
    required this.onJump,
  });
  final WordDocumentIndex index;
  final bool enabled;
  final ValueChanged<int> onJump;
  @override
  State<WordNavigationPanel> createState() => _WordNavigationPanelState();
}

class _WordNavigationPanelState extends State<WordNavigationPanel> {
  final number = TextEditingController();
  String query = '';
  bool invalidNumber = false;
  @override
  void dispose() {
    number.dispose();
    super.dispose();
  }

  void go() {
    final target = int.tryParse(number.text.trim());
    if (target == null || target < 1 || target > widget.index.blocks.length) {
      setState(() => invalidNumber = true);
      return;
    }
    if (widget.enabled) widget.onJump(target - 1);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.index.blocks.length;
    final enabled = widget.enabled && count > 0;
    final headings = widget.index.headings
        .where((h) => h.text.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiText('Абзацев основного текста: $count'),
        const UiText('Таблицы и колонтитулы не включены'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('word-jump-start'),
              onPressed: enabled ? () => widget.onJump(0) : null,
              icon: const Icon(Icons.vertical_align_top),
              label: const UiText('В начало документа'),
            ),
            OutlinedButton.icon(
              key: const Key('word-jump-end'),
              onPressed: enabled ? () => widget.onJump(count - 1) : null,
              icon: const Icon(Icons.vertical_align_bottom),
              label: const UiText('В конец документа'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('word-jump-number'),
          controller: number,
          enabled: enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => go(),
          onChanged: (_) {
            if (invalidNumber) setState(() => invalidNumber = false);
          },
          decoration: InputDecoration(
            labelText: tr(context, 'Номер абзаца'),
            helperText: tr(context, 'От 1 до $count'),
            errorText: invalidNumber
                ? tr(context, 'Введите номер от 1 до $count')
                : null,
            suffixIcon: IconButton(
              tooltip: tr(context, 'Перейти к абзацу'),
              onPressed: enabled ? go : null,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('word-heading-filter'),
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            labelText: tr(context, 'Найти заголовок'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.index.headings.isEmpty)
          const UiText('В документе нет заголовков с уровнем структуры')
        else if (headings.isEmpty)
          const UiText('Заголовки не найдены')
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              key: const Key('word-heading-list'),
              itemCount: headings.length,
              itemBuilder: (_, i) {
                final heading = headings[i];
                return ListTile(
                  key: ValueKey(('word-heading', heading.position)),
                  contentPadding: EdgeInsets.only(
                    left: heading.level.clamp(0, 4) * 12.0,
                    right: 8,
                  ),
                  leading: Text('${heading.level + 1}'),
                  title: Text(
                    heading.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: enabled ? () => widget.onJump(heading.position) : null,
                );
              },
            ),
          ),
      ],
    );
  }
}
