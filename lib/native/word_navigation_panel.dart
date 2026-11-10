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
  final headingQuery = TextEditingController();
  bool invalidNumber = false;
  @override
  void dispose() {
    number.dispose();
    headingQuery.dispose();
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
    final query = headingQuery.text.toLowerCase();
    final headings = widget.index.headings
        .where((h) => h.text.toLowerCase().contains(query))
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
            helperText: count > 0 ? tr(context, 'От 1 до $count') : null,
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
          controller: headingQuery,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr(context, 'Найти заголовок'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: headingQuery.text.isEmpty
                ? null
                : IconButton(
                    tooltip: tr(context, 'Очистить поиск'),
                    onPressed: () => setState(headingQuery.clear),
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.index.headings.isEmpty)
          const UiText('В документе нет заголовков с уровнем структуры')
        else if (headings.isEmpty)
          const UiText('Заголовки не найдены')
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              // Only short result sets shrink; large outlines stay lazy.
              shrinkWrap: headings.length <= 4,
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
