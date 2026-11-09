import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

/// The dialog owns its TextFormField through the entire route transition.
/// No caller-managed TextEditingController is disposed before unmount.
Future<String?> showDeckTextDialog(
  BuildContext context,
  String heading, {
  String initial = '',
}) {
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: UiText(heading),
      content: TextFormField(
        initialValue: initial,
        onChanged: (next) => value = next,
        maxLines: 3,
        autofocus: true,
        decoration: InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const UiText('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, value),
          child: const UiText('Применить'),
        ),
      ],
    ),
  );
}
