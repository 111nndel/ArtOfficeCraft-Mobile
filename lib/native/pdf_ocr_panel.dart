import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import 'pdf_page_renderer.dart';

class PdfOcrPanel extends StatefulWidget {
  const PdfOcrPanel({
    super.key,
    required this.recognize,
    required this.addLayer,
  });

  final Future<PdfOcrResult> Function()? recognize;
  final ValueChanged<List<PdfOcrWord>>? addLayer;

  @override
  State<PdfOcrPanel> createState() => _PdfOcrPanelState();
}

class _PdfOcrPanelState extends State<PdfOcrPanel> {
  bool _running = false, _failed = false;
  PdfOcrResult? _result;

  Future<void> _run(Future<PdfOcrResult> Function() recognize) async {
    setState(() {
      _running = true;
      _failed = false;
      _result = null;
    });
    try {
      final result = await recognize();
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recognize = widget.recognize;
    final result = _result;
    final text = result?.text;
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
          if (result!.words.isNotEmpty)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.addLayer == null
                  ? null
                  : () => widget.addLayer!(result.words),
              child: const UiText('Добавить текстовый слой'),
            )
          else
            const UiText('Координаты текста недоступны для сохранения'),
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
