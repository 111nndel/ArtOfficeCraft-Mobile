import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

typedef PdfBookmark = ({String title, int? page, int depth});

class PdfOutlinePanel extends StatefulWidget {
  const PdfOutlinePanel({
    super.key,
    required this.entries,
    required this.limited,
    required this.onJump,
  });

  final List<PdfBookmark> entries;
  final bool limited;
  final ValueChanged<int>? onJump;

  @override
  State<PdfOutlinePanel> createState() => _PdfOutlinePanelState();
}

class _PdfOutlinePanelState extends State<PdfOutlinePanel> {
  final scroll = ScrollController();
  String query = '';

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const UiText('В этом PDF нет закладок');
    }
    final matches = query.isEmpty
        ? widget.entries
        : widget.entries
              .where((entry) => entry.title.toLowerCase().contains(query))
              .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('pdf-bookmark-search'),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: tr(context, 'Поиск по оглавлению'),
          ),
          onChanged: (value) {
            if (scroll.hasClients) scroll.jumpTo(0);
            setState(() => query = value.trim().toLowerCase());
          },
        ),
        if (widget.limited) ...[
          const SizedBox(height: 8),
          const UiText('Показаны первые 4096 закладок'),
        ],
        const SizedBox(height: 8),
        if (matches.isEmpty)
          const UiText('Закладки не найдены')
        else
          SizedBox(
            height: (matches.length * 64.0).clamp(64.0, 232.0),
            child: Scrollbar(
              controller: scroll,
              child: ListView.builder(
                controller: scroll,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final entry = matches[index];
                  final page = entry.page;
                  return ListTile(
                    minTileHeight: 56,
                    contentPadding: EdgeInsetsDirectional.only(
                      start: 4 + entry.depth.clamp(0, 5) * 10.0,
                      end: 12,
                    ),
                    title: entry.title.isEmpty
                        ? const UiText('Закладка без названия')
                        : Text(entry.title),
                    trailing: page == null ? null : Text('${page + 1}'),
                    onTap: page == null || widget.onJump == null
                        ? null
                        : () => widget.onJump!(page),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
