import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

class EditorCommand {
  const EditorCommand(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

/// A leaf command, a nested list, or an inline form within the same tool slab.
class EditorTool {
  const EditorTool(
    this.label,
    this.icon, {
    this.onPressed,
    this.children,
    this.builder,
    this.pending = false,
    this.inline = false,
    this.localize = true,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final List<EditorTool>? children;
  final WidgetBuilder? builder;
  final bool pending, inline, localize;
}

class EditorSection {
  const EditorSection(this.label, this.tools);
  final String label;
  final List<EditorTool> tools;
}

class EditorToolPanel extends StatefulWidget {
  const EditorToolPanel({
    super.key,
    required this.sections,
    required this.color,
    this.onExpandedChanged,
    this.undo,
    this.redo,
  });
  final List<EditorSection> sections;
  final Color color;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? undo, redo;
  @override
  State<EditorToolPanel> createState() => EditorToolPanelState();
}

class EditorToolPanelState extends State<EditorToolPanel> {
  final _link = LayerLink();
  final _overlay = OverlayPortalController();
  final _anchor = GlobalKey();
  final Map<String, ScrollController> _scroll = {};
  final Map<String, List<int>> _visited = {'0': []};
  int _section = 0;
  List<int> _path = [];
  bool expanded = false;
  String get _id => '$_section${_path.map((i) => '/$i').join()}';
  bool isShowing(String label) =>
      expanded && _tool(_section, _path)?.label == label;

  void setExpanded(bool value) {
    if (_overlay.isShowing) _overlay.hide();
    setState(() => expanded = value);
    widget.onExpandedChanged?.call(value);
    if (value) FocusManager.instance.primaryFocus?.unfocus();
  }

  void openTool(int section, List<int> path) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _section = section;
      _path = path;
      _visited[_id] = List.of(path);
      expanded = true;
    });
    if (_overlay.isShowing) _overlay.hide();
    widget.onExpandedChanged?.call(true);
  }

  void back() {
    if (_path.isEmpty) return;
    openTool(_section, _path.sublist(0, _path.length - 1));
  }

  void handleBack() {
    if (_overlay.isShowing) {
      _overlay.hide();
    } else if (_path.isNotEmpty) {
      back();
    } else if (expanded) {
      setExpanded(false);
    }
  }

  @override
  void dispose() {
    for (final c in _scroll.values) {
      c.dispose();
    }
    super.dispose();
  }

  EditorTool? _tool(int section, List<int> path) {
    var tools = widget.sections[section].tools;
    EditorTool? result;
    for (final i in path) {
      if (i >= tools.length) return null;
      result = tools[i];
      tools = result.children ?? [];
    }
    return result;
  }

  Widget _button(String label, IconData icon, VoidCallback? action) =>
      SizedBox.square(
        dimension: 52,
        child: IconButton(
          tooltip: tr(context, label),
          onPressed: action,
          icon: Icon(icon, size: 26),
          style: IconButton.styleFrom(
            minimumSize: const Size(52, 52),
            padding: const EdgeInsets.all(12),
          ),
        ),
      );
  Widget _menu() {
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const SizedBox.shrink();
    final top = box.localToGlobal(Offset.zero).dy;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _overlay.hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 16).clamp(240.0, 300.0),
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (top - MediaQuery.paddingOf(context).top - 8)
                      .clamp(100.0, 520.0),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.sections.length; i++)
                        ListTile(
                          key: ValueKey('section-menu-$i'),
                          minTileHeight: 52,
                          selected: i == _section,
                          selectedTileColor: widget.color.withValues(
                            alpha: .09,
                          ),
                          selectedColor: widget.color,
                          title: UiText(widget.sections[i].label),
                          onTap: () => openTool(i, []),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pane(int section, List<int> path, String id) {
    final tool = _tool(section, path);
    final tools = path.isEmpty
        ? widget.sections[section].tools
        : tool?.children ?? [];
    return SingleChildScrollView(
      key: ValueKey('pane-$id'),
      controller: _scroll.putIfAbsent(id, ScrollController.new),
      child: tool?.builder != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: tool!.builder!(context),
            )
          : Column(
              children: [
                for (var i = 0; i < tools.length; i++)
                  if (tools[i].inline && tools[i].builder != null)
                    tools[i].builder!(context)
                  else
                    ListTile(
                      minTileHeight: 56,
                      leading: Icon(
                        tools[i].icon,
                        color: tools[i].pending
                            ? Theme.of(context).disabledColor
                            : widget.color,
                      ),
                      title: UiText(
                        tools[i].label,
                        translate: tools[i].localize,
                      ),
                      subtitle: tools[i].pending
                          ? const UiText(
                              'Ещё не подключено',
                              style: TextStyle(fontSize: 13),
                            )
                          : null,
                      enabled:
                          !tools[i].pending &&
                          (tools[i].onPressed != null ||
                              tools[i].children != null ||
                              tools[i].builder != null),
                      trailing:
                          tools[i].children != null || tools[i].builder != null
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap:
                          tools[i].children != null || tools[i].builder != null
                          ? () => openTool(section, [...path, i])
                          : tools[i].onPressed,
                    ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = expanded && _path.isNotEmpty
        ? _tool(_section, _path)?.label ?? widget.sections[_section].label
        : widget.sections[_section].label;
    final media = MediaQuery.of(context);
    // Remain usable in landscape and with the keyboard, retaining the canvas.
    final height =
        ((media.size.height -
                    media.viewInsets.bottom -
                    media.padding.vertical) *
                .36)
            .clamp(90.0, 290.0);
    final ids = _visited.keys.toList();
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: widget.color,
          primaryContainer: widget.color.withValues(alpha: .12),
        ),
      ),
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (_) => _menu(),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CompositedTransformTarget(
                  link: _link,
                  child: Container(
                    key: _anchor,
                    margin: EdgeInsets.fromLTRB(
                      expanded ? 0 : 8,
                      0,
                      expanded ? 0 : 8,
                      0,
                    ),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(expanded ? 0 : 16),
                    ),
                    child: Row(
                      children: [
                        if (expanded && _path.isNotEmpty)
                          _button(
                            'Назад к инструментам',
                            Icons.arrow_back,
                            back,
                          ),
                        Expanded(
                          child: InkWell(
                            key: const Key('tool-section-caption'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (_overlay.isShowing) {
                                _overlay.hide();
                              } else {
                                if (!expanded) setExpanded(true);
                                _overlay.show();
                              }
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 56),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: UiText(
                                        title,
                                        translate:
                                            _path.isEmpty ||
                                            _tool(_section, _path)?.localize !=
                                                false,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.unfold_more, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_path.isEmpty || !expanded) ...[
                          _button('Отменить', Icons.undo, widget.undo),
                          _button('Повторить', Icons.redo, widget.redo),
                        ],
                        _button(
                          expanded
                              ? 'Свернуть инструменты'
                              : 'Развернуть инструменты',
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          () => setExpanded(!expanded),
                        ),
                      ],
                    ),
                  ),
                ),
                Offstage(
                  offstage: !expanded,
                  child: SizedBox(
                    height: height,
                    child: IndexedStack(
                      index: ids.indexOf(_id).clamp(0, ids.length - 1),
                      children: [
                        for (final id in ids)
                          _pane(
                            int.parse(id.split('/').first),
                            _visited[id]!,
                            id,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// File commands are separate from document tools; no duplicate Save row.
class EditorFileMenu extends StatelessWidget {
  const EditorFileMenu({super.key, required this.commands});
  final List<EditorCommand> commands;
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: tr(context, 'Меню файла'),
    icon: const Icon(Icons.more_horiz),
    onSelected: (i) => commands[i].onPressed?.call(),
    itemBuilder: (_) => [
      for (var i = 0; i < commands.length; i++)
        PopupMenuItem(
          value: i,
          enabled: commands[i].onPressed != null,
          height: 56,
          child: Row(
            children: [
              Icon(commands[i].icon),
              const SizedBox(width: 12),
              Expanded(child: UiText(commands[i].label)),
            ],
          ),
        ),
    ],
  );
}

class EditorWelcome extends StatelessWidget {
  const EditorWelcome({
    super.key,
    required this.icon,
    required this.title,
    required this.openLabel,
    required this.createLabel,
    required this.onOpen,
    required this.onCreate,
    required this.busy,
  });
  final IconData icon;
  final String title, openLabel, createLabel;
  final VoidCallback? onOpen, onCreate;
  final bool busy;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 18),
          UiText(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.folder_open_outlined),
            label: UiText(openLabel),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onCreate,
            icon: const Icon(Icons.add),
            label: UiText(createLabel),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    ),
  );
}

class EditorTextStyleControls extends StatelessWidget {
  const EditorTextStyleControls({
    super.key,
    this.onBold,
    this.onItalic,
    this.onUnderline,
    this.onSize,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontSize,
  });
  final VoidCallback? onBold, onItalic, onUnderline;
  final ValueChanged<double>? onSize;
  final bool bold, italic, underline;
  final double? fontSize;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Expanded(
              child: UiText('Шрифт и стиль', style: TextStyle(fontSize: 16)),
            ),
            DropdownButton<double>(
              hint: const UiText('Размер'),
              value: fontSize,
              onChanged: onSize == null
                  ? null
                  : (v) {
                      if (v != null) onSize!(v);
                    },
              items: {?fontSize, 10.0, 12.0, 14.0, 16.0, 18.0, 24.0, 32.0}
                  .toList()
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: UiText(v.toInt().toString()),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final command in [
            EditorCommand('Жирный', Icons.format_bold, onBold),
            EditorCommand('Курсив', Icons.format_italic, onItalic),
            EditorCommand('Подчеркнуть', Icons.format_underlined, onUnderline),
          ])
            SizedBox.square(
              dimension: 56,
              child: IconButton(
                isSelected: command.icon == Icons.format_bold
                    ? bold
                    : command.icon == Icons.format_italic
                    ? italic
                    : underline,
                tooltip: tr(context, command.label),
                onPressed: command.onPressed,
                icon: Icon(command.icon, size: 28),
              ),
            ),
        ],
      ),
      const Divider(height: 1),
    ],
  );
}
