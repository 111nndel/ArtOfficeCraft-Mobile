import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

typedef NoticeAction = ({String label, VoidCallback onPressed});

/// Keep full text scaling and wrap actions within the actual available width.
/// The framework's action-width estimate does not account for scaled labels.
SnackBar transientNotice(
  String message, {
  Duration duration = const Duration(seconds: 5),
  NoticeAction? action,
}) => SnackBar(
  duration: duration,
  persist: false,
  showCloseIcon: true,
  content: Builder(
    builder: (context) => Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        UiText(message),
        if (action != null)
          SnackBarAction(
            label: tr(context, action.label),
            onPressed: action.onPressed,
          ),
      ],
    ),
  ),
);
