import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class DeckSearchPanel extends StatefulWidget {
  const DeckSearchPanel({
    super.key,
    required this.slides,
    required this.onJump,
  });

  final List<Map<String, dynamic>> slides;
  final ValueChanged<int>? onJump;

  @override
  State<DeckSearchPanel> createState() => _DeckSearchPanelState();
}

class _DeckSearchPanelState extends State<DeckSearchPanel> {
  String query = '';
  bool includeNotes = false;
  List<({int slide, String text, bool inNotes})> matches = const [];

  @override
  void didUpdateWidget(DeckSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.slides, widget.slides)) search(query);
  }

  void search(String input) {
    query = input.trim();
    matches = [];
    if (query.isEmpty) return;
    final pattern = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
      unicode: true,
    );
    for (var i = 0; i < widget.slides.length; i++) {
      final slide = widget.slides[i];
      final parts = [
        (slide['title'], false),
        for (final shape
            in (slide['shapes'] as List? ?? const []).whereType<Map>())
          (shape['text'], false),
        if (includeNotes) (slide['notes'], true),
      ];
      for (final (text, inNotes) in parts) {
        if (text is! String) continue;
        final hit = pattern.firstMatch(text);
        if (hit == null) continue;
        matches.add((
          slide: i,
          text: text.substring(hit.start),
          inNotes: inNotes,
        ));
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('deck-search'),
        decoration: InputDecoration(labelText: tr(context, 'Текст для поиска')),
        onChanged: (input) => setState(() => search(input)),
      ),
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const UiText('Искать в заметках докладчика'),
        value: includeNotes,
        onChanged: (value) => setState(() {
          includeNotes = value == true;
          search(query);
        }),
      ),
      if (widget.slides.any((s) => s['truncated'] == true))
        const UiText('Поиск ограничен первыми 120 объектами каждого слайда.'),
      if (query.isNotEmpty && matches.isEmpty) const UiText('Совпадений нет'),
      if (matches.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            shrinkWrap: matches.length <= 3,
            itemCount: matches.length,
            itemBuilder: (_, i) {
              final hit = matches[i];
              return ListTile(
                key: ValueKey(('slide-match', hit.slide)),
                title: Row(
                  children: [
                    UiText('Слайд ${hit.slide + 1}'),
                    if (hit.inNotes) ...[
                      const SizedBox(width: 8),
                      const Flexible(child: UiText('Заметки')),
                    ],
                  ],
                ),
                subtitle: Text(
                  hit.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: widget.onJump == null
                    ? null
                    : () => widget.onJump!(hit.slide),
              );
            },
          ),
        ),
    ],
  );
}
