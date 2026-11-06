import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';

class PdfOcrPanel extends StatefulWidget {
  const PdfOcrPanel({super.key, required this.recognize});

  final Future<String> Function()? recognize;

  @override
  State<PdfOcrPanel> createState() => _PdfOcrPanelState();
}

class _PdfOcrPanelState extends State<PdfOcrPanel> {
  bool _running = false, _failed = false;
  String? _text;

  Future<void> _run(Future<String> Function() recognize) async {
    setState(() {
      _running = true;
      _failed = false;
      _text = null;
    });
    try {
      final text = await recognize();
      if (mounted) setState(() => _text = text);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recognize = widget.recognize;
    final text = _text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UiText('Русский и английский · на устройстве'),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _running || recognize == null
              ? null
              : () => _run(recognize),
          child: const UiText('Распознать страницу'),
        ),
        if (_running) ...[
          const LinearProgressIndicator(),
          const UiText('Распознаём текст…'),
        ],
        if (_failed) const UiText('Не удалось распознать страницу'),
        if (text != null && text.isEmpty)
          const UiText('На странице не распознан текст'),
        if (text != null && text.isNotEmpty) ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: UiText('Распознанный текст скопирован'),
                ),
              );
            },
            child: const UiText('Скопировать распознанный текст'),
          ),
          SelectableText(text, key: const Key('pdf-ocr-result')),
        ],
      ],
    );
  }
}
