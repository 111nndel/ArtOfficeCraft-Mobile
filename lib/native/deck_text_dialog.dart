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
      title: Text(heading),
      content: TextFormField(
        initialValue: initial,
        onChanged: (next) => value = next,
        maxLines: 3,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, value),
          child: const Text('Применить'),
        ),
      ],
    ),
  );
}
