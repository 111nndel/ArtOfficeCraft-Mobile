import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

/// Blocks Back while an editor is writing a file or has unsaved changes.
/// Applies equally to the AppBar Back button and Android system Back.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
    this.interceptBack = false,
    this.onInterceptBack,
    this.onDiscard,
  });

  final bool dirty;
  final bool busy;
  final Widget child;
  final bool interceptBack;
  final VoidCallback? onInterceptBack;
  final Future<void> Function()? onDiscard;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allowExit = false;
  bool _dialogOpen = false;

  Future<void> _onPop(bool didPop) async {
    if (didPop || !mounted || _dialogOpen || _allowExit) return;
    if (widget.interceptBack) {
      widget.onInterceptBack?.call();
      return;
    }
    if (widget.busy) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: UiText('Дождитесь завершения операции с файлом'),
        ),
      );
      return;
    }
    if (!widget.dirty) return;
    _dialogOpen = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const UiText('Несохранённые изменения'),
          content: const UiText(
            'Изменения не сохранены. Выйти из редактора без сохранения копии?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const UiText('Остаться'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const UiText('Выйти без сохранения'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      try {
        await widget.onDiscard?.call();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: UiText(
                'Не удалось удалить черновик. Работа оставлена открытой.',
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _allowExit = true);
      // Wait until PopScope registers canPop=true before navigating.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop:
          _allowExit ||
          (!widget.dirty && !widget.busy && !widget.interceptBack),
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: widget.child,
    );
  }
}
