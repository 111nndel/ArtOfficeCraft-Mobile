import 'package:flutter/material.dart';

/// Blocks Back while an editor is writing a file or has unsaved changes.
/// Applies equally to the AppBar Back button and Android system Back.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
  });

  final bool dirty;
  final bool busy;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allowExit = false;
  bool _dialogOpen = false;

  Future<void> _onPop(bool didPop) async {
    if (didPop || !mounted || _dialogOpen || _allowExit) return;
    if (widget.busy) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Дождитесь завершения операции с файлом')),
      );
      return;
    }
    if (!widget.dirty) return;
    _dialogOpen = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Несохранённые изменения'),
          content: const Text(
            'Изменения не сохранены. Выйти из редактора без сохранения копии?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Остаться'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Выйти без сохранения'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
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
      canPop: _allowExit || (!widget.dirty && !widget.busy),
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: widget.child,
    );
  }
}
