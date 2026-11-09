import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'document_backend.dart';
import 'grid_window.dart';

String gridFilterError(Object error) => switch (error) {
  FormatException(
    message: 'Select a header and up to 4096 data rows and 128 columns',
  ) =>
    'Выделите заголовок и до 4096 строк данных и 128 столбцов',
  FormatException(message: 'The filter header row must be visible') =>
    'Строка заголовка должна быть видимой',
  FormatException(message: 'This AutoFilter uses unsupported criteria') =>
    'Этот тип автофильтра пока нельзя изменить',
  FormatException(
    message: 'Select a range without merged cells or Excel tables',
  ) =>
    'Выберите диапазон без объединённых ячеек и таблиц Excel',
  FormatException(
    message: 'Filter range includes manually hidden or grouped rows',
  ) =>
    'В диапазоне есть строки, скрытые вручную или группировкой',
  FormatException(message: 'This column has too many distinct filter values') =>
    'В столбце слишком много разных значений для фильтра',
  FormatException(
    message: 'This filter groups identical displayed values differently',
  ) =>
    'В этом фильтре одинаково выглядящие ячейки имеют разные условия',
  FormatException(
    message: 'Some filter values overlap because of number formatting',
  ) =>
    'Из-за числового формата часть значений нельзя отфильтровать отдельно',
  _ => 'Не удалось применить или прочитать фильтр',
};

/// Edits one column's values in the existing tools panel.
class GridFilterPanel extends StatefulWidget {
  const GridFilterPanel({
    super.key,
    required this.source,
    required this.range,
    required this.columns,
    required this.initialColumn,
    required this.load,
    required this.onApply,
    required this.onRemove,
  });

  final Uint8List source;
  final String range;
  final List<int> columns;
  final int initialColumn;
  final Future<List<GridFilterChoice>> Function(int column) load;
  final void Function(int column, Set<String?> values)? onApply;
  final VoidCallback? onRemove;

  @override
  State<GridFilterPanel> createState() => _GridFilterPanelState();
}

class _GridFilterPanelState extends State<GridFilterPanel> {
  late int _column;
  late Future<List<GridFilterChoice>> _options;
  Set<String?>? _selection;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _column = widget.initialColumn;
    _refresh();
  }

  @override
  void didUpdateWidget(GridFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      if (!widget.columns.contains(_column)) _column = widget.initialColumn;
      _refresh();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    _selection = null;
    _options = widget.load(_column);
  }

  Widget _choices(AsyncSnapshot<List<GridFilterChoice>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: LinearProgressIndicator(),
      );
    }
    if (snapshot.hasError) return UiText(gridFilterError(snapshot.error!));
    final items = snapshot.requireData;
    final initial = {
      for (final item in items)
        if (item.checked) item.value,
    };
    final selection = _selection ?? initial;
    final all = selection.length == items.length;
    final enabled = widget.onApply != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          title: const UiText('Выбрать все значения'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          value: all,
          onChanged: enabled
              ? (checked) => setState(() {
                  _selection = checked == true
                      ? {for (final item in items) item.value}
                      : {};
                })
              : null,
        ),
        SizedBox(
          height: (items.length * 56.0).clamp(56.0, 168.0),
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              key: ValueKey(_column),
              controller: _scroll,
              itemCount: items.length,
              itemBuilder: (_, index) {
                final value = items[index].value;
                return CheckboxListTile(
                  key: ValueKey(('filter-value', value)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  value: selection.contains(value),
                  title: switch (value) {
                    null => const UiText('(Пустые ячейки)'),
                    '' => const UiText('(Скрыто числовым форматом)'),
                    _ => Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  },
                  onChanged: enabled
                      ? (checked) {
                          setState(() {
                            final next = {...selection};
                            if (checked == true) {
                              next.add(value);
                            } else {
                              next.remove(value);
                            }
                            _selection = next;
                          });
                        }
                      : null,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed:
              !enabled || selection.isEmpty || setEquals(initial, selection)
              ? null
              : () => widget.onApply!(_column, selection),
          icon: const Icon(Icons.filter_alt),
          label: const UiText('Применить фильтр'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.range, style: Theme.of(context).textTheme.titleMedium),
      const UiText('Первая строка остаётся заголовком.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey(('filter-column', _column)),
        initialValue: _column,
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: InputDecoration(labelText: tr(context, 'Столбец фильтра')),
        items: [
          for (final col in widget.columns)
            DropdownMenuItem(value: col, child: Text(gridColumnName(col))),
        ],
        onChanged: widget.onApply == null
            ? null
            : (value) {
                if (value == null || value == _column) return;
                setState(() {
                  _column = value;
                  _refresh();
                });
              },
      ),
      FutureBuilder<List<GridFilterChoice>>(
        future: _options,
        builder: (_, snapshot) => _choices(snapshot),
      ),
      if (widget.onRemove != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: widget.onRemove,
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const UiText('Снять автофильтр'),
        ),
      ],
    ],
  );
}
