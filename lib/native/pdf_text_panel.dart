import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'document_backend.dart';

class PdfTextPanel extends StatefulWidget {
  const PdfTextPanel({
    super.key,
    required this.load,
    required this.onApply,
    required this.busy,
  });

  final Future<PdfTextPage> Function() load;
  final Future<void> Function(PdfTextBlock, String) onApply;
  final bool busy;

  @override
  State<PdfTextPanel> createState() => _PdfTextPanelState();
}

class _PdfTextPanelState extends State<PdfTextPanel> {
  late final _page = widget.load();
  final _draft = TextEditingController();
  PdfTextBlock? _selected;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = _selected;
    if (block != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('pdf-page-text-input'),
            controller: _draft,
            readOnly: widget.busy,
            minLines: 2,
            maxLines: 4,
            maxLength: 4096,
            decoration: InputDecoration(
              labelText: tr(context, 'Текст абзаца PDF'),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _draft,
                builder: (_, value, _) => FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed:
                      widget.busy ||
                          value.text.trim().isEmpty ||
                          value.text == block.text
                      ? null
                      : () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          widget.onApply(block, value.text);
                        },
                  child: const UiText('Применить правку текста'),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: widget.busy
                    ? null
                    : () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => _selected = null);
                      },
                child: const UiText('Отмена'),
              ),
            ],
          ),
        ],
      );
    }
    return FutureBuilder<PdfTextPage>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return UiText('PDFCraft: ${snapshot.error}');
        }
        final page = snapshot.data;
        if (page == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (page.blocks.isEmpty) {
          return const UiText('На странице нет доступного для правки текста');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const UiText('Выберите текст на текущей странице'),
            if (page.limited)
              const UiText('Показаны первые 256 текстовых блоков'),
            SizedBox(
              height: (page.blocks.length * 64.0).clamp(64.0, 224.0),
              child: ListView.builder(
                primary: false,
                itemCount: page.blocks.length,
                itemBuilder: (_, index) {
                  final item = page.blocks[index];
                  return ListTile(
                    key: ValueKey('pdf-page-text-${item.id}'),
                    minTileHeight: 56,
                    title: Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: widget.busy
                        ? null
                        : () {
                            _draft.text = item.text;
                            setState(() => _selected = item);
                          },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
