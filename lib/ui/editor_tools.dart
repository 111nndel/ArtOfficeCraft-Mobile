import 'package:flutter/material.dart';

class EditorCommand {
  const EditorCommand(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class EditorToolSection {
  const EditorToolSection(this.label, this.commands);
  final String label;
  final List<EditorCommand> commands;
}

/// The same thumb-sized commands on phones and tablets. No fixed text clipping.
class EditorCommandBar extends StatelessWidget {
  const EditorCommandBar({super.key, required this.commands, this.color});
  final List<EditorCommand> commands;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.textScalerOf(context).scale(15) * 1.5 + 30)
        .clamp(68.0, 150.0);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final command in commands)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: command.onPressed,
                    icon: Icon(command.icon, color: color),
                    label: Text(command.label),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(52, 52),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditorSectionTabs extends StatefulWidget implements PreferredSizeWidget {
  const EditorSectionTabs({
    super.key,
    required this.sections,
    required this.color,
    this.height = 56,
  });
  final List<EditorToolSection> sections;
  final Color color;
  final double height;
  @override
  Size get preferredSize => Size.fromHeight(height);
  @override
  State<EditorSectionTabs> createState() => _EditorSectionTabsState();
}

class _EditorSectionTabsState extends State<EditorSectionTabs> {
  int selected = 0;
  Future<void> showCommands(int index) async {
    setState(() => selected = index);
    final section = widget.sections[index];
    final command = await showModalBottomSheet<EditorCommand>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                section.label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final action in section.commands)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    onPressed: action.onPressed == null
                        ? null
                        : () => Navigator.pop(context, action),
                    icon: Icon(action.icon, color: widget.color),
                    label: Text(action.label),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(52, 56),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) command?.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < widget.sections.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: TextButton(
              onPressed: () => showCommands(i),
              style: TextButton.styleFrom(
                foregroundColor: selected == i
                    ? widget.color
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                shape: const RoundedRectangleBorder(),
                minimumSize: const Size(52, 52),
                side: selected == i
                    ? BorderSide(color: widget.color, width: 1)
                    : BorderSide.none,
              ),
              child: Text(
                widget.sections[i].label,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
      ],
    ),
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
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(openLabel),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onCreate,
            icon: const Icon(Icons.add),
            label: Text(createLabel),
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
