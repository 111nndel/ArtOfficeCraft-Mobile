import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

/// Labelled, touch-friendly actions that scroll on small portrait screens.
class PdfPageActionBar extends StatelessWidget {
  const PdfPageActionBar({
    super.key,
    required this.selected,
    required this.pageCount,
    required this.busy,
    required this.onAction,
  });

  final int selected;
  final int pageCount;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    Widget action(String name, IconData icon, String text, bool enabled) {
      return OutlinedButton.icon(
        onPressed: enabled && !busy ? () => onAction(name) : null,
        icon: Icon(icon, size: 20),
        label: UiText(text, maxLines: 1),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );
    }

    final pageNumber = selected + 1;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: UiText(
              'Страница $pageNumber из $pageCount · действия листаются вбок',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            height: 68,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              children: [
                action('move_up', Icons.arrow_back, 'Раньше', selected > 0),
                const SizedBox(width: 6),
                action(
                  'move_down',
                  Icons.arrow_forward,
                  'Позже',
                  selected + 1 < pageCount,
                ),
                const SizedBox(width: 6),
                action('rotate_ccw', Icons.rotate_left, 'Влево', pageCount > 0),
                const SizedBox(width: 6),
                action(
                  'rotate_cw',
                  Icons.rotate_right,
                  'Вправо',
                  pageCount > 0,
                ),
                const SizedBox(width: 6),
                action('duplicate', Icons.copy, 'Копировать', pageCount > 0),
                const SizedBox(width: 6),
                action(
                  'insert_blank',
                  Icons.note_add_outlined,
                  'Вставить',
                  pageCount > 0,
                ),
                const SizedBox(width: 6),
                action(
                  'delete',
                  Icons.delete_outline,
                  'Удалить',
                  pageCount > 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
