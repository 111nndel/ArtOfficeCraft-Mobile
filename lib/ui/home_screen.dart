import 'project_info_screen.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../native/imported_filename.dart';
import '../native/native_deck_screen.dart';
import '../native/native_grid_screen.dart';
import '../native/native_pdf_screen.dart';
import '../native/native_word_screen.dart';
import '../workspace/editor_kind.dart';
import '../workspace/editor_launch.dart';
import '../workspace/workspace_store.dart';
import 'office_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.toggleTheme,
    required this.theme,
    this.workspace,
  });
  final VoidCallback toggleTheme;
  final ThemeMode theme;
  final WorkspaceStore? workspace;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final WorkspaceStore store = widget.workspace ?? WorkspaceStore();
  final search = TextEditingController();
  int section = 0;
  EditorKind? filter;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    store.addListener(refresh);
    if (!store.loaded) store.load();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(refresh);
    if (widget.workspace == null) store.dispose();
    search.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> open(
    EditorKind kind, {
    EditorLaunch? launch,
    WorkspaceFile? entry,
  }) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      if (entry != null) {
        launch = EditorLaunch(bytes: await store.read(entry), name: entry.name);
      }
      if (!mounted) return;
      String? id = entry?.id;
      Future<void> remember(Uint8List bytes, String name) async {
        final saved = await store.remember(kind, bytes, name, id: id);
        id = saved.id;
      }

      final screen = switch (kind) {
        EditorKind.word => NativeWordScreen(
          launch: launch,
          onRemember: remember,
        ),
        EditorKind.excel => NativeGridScreen(
          launch: launch,
          onRemember: remember,
        ),
        EditorKind.slides => NativeDeckScreen(
          launch: launch,
          onRemember: remember,
        ),
        EditorKind.pdf => NativePdfScreen(launch: launch, onRemember: remember),
      };
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
    } catch (_) {
      message(
        'Не удалось открыть рабочую копию. Попробуйте открыть исходный файл с устройства.',
      );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> chooseKind({bool create = false}) async {
    final kind = await showModalBottomSheet<EditorKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  create ? 'Что создадим?' : 'Какой файл открыть?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                for (final k in EditorKind.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      minTileHeight: 68,
                      leading: FormatIcon(kind: k),
                      title: Text(k.label),
                      subtitle: Text(k.format),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, k),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (create) {
      await open(kind, launch: const EditorLaunch(create: true));
    } else {
      try {
        final path = await FlutterFileDialog.pickFile();
        if (path == null || !mounted) return;
        final file = File(path);
        if (await file.length() > 64 * 1024 * 1024) {
          message('Для этой версии выберите файл до 64 МБ.');
          return;
        }
        final bytes = await file.readAsBytes();
        if (mounted) {
          await open(
            kind,
            launch: EditorLaunch(
              bytes: bytes,
              name: importedFilename(path, kind.extension),
            ),
          );
        }
      } catch (_) {
        message('Не удалось прочитать выбранный файл.');
      }
    }
  }

  Future<void> favorite(WorkspaceFile file) async {
    try {
      await store.toggleFavorite(file);
    } catch (_) {
      message('Не удалось сохранить избранное.');
    }
  }

  String get title => switch (section) {
    1 => 'Все файлы',
    2 => 'Всегда под рукой',
    3 => 'Начните с хорошей основы',
    _ => 'Ваши идеи.\nВаше пространство.',
  };
  void selectSection(int value) => setState(() {
    section = value;
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final searching = search.text.trim().isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: OfficeTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'a',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'ArtOfficeCraft',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'О проекте и лицензиях',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProjectInfoScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Изменить тему',
            onPressed: widget.toggleTheme,
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 224,
              child: ColoredBox(
                color: colors.surface,
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    for (final i in [0, 1, 2, 3])
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          minTileHeight: 56,
                          selected: section == i,
                          selectedTileColor: colors.primaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(navIcon(i)),
                          title: Text(navLabel(i)),
                          onTap: () => selectSection(i),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.icon(
                        onPressed: () => chooseKind(create: true),
                        icon: const Icon(Icons.add),
                        label: const Text('Создать'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  key: const PageStorageKey('workspace-scroll'),
                  padding: EdgeInsets.all(wide ? 32 : 20),
                  children: [
                    TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Найти файл',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Очистить поиск',
                                onPressed: () => setState(() => search.clear()),
                                icon: const Icon(Icons.close),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (!searching) ...[
                      const SizedBox(height: 28),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: wide ? 32 : 29,
                          height: 1.15,
                          letterSpacing: -.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        section == 3
                            ? 'Продуманные заготовки для ваших задач.'
                            : 'Документы, расчёты и большие замыслы.\nВсё в одном пространстве.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (!searching && section != 2 && section != 3) ...[
                      const Text(
                        'Создать файл',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final scale = MediaQuery.textScalerOf(context)
                              .scale(1);
                          final columns =
                              constraints.maxWidth >= 800 && scale <= 1.3
                              ? 4
                              : constraints.maxWidth >=
                                    (scale > 1.3 ? 600 : 300)
                              ? 2
                              : 1;
                          final width =
                              (constraints.maxWidth - 12 * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final kind in EditorKind.values)
                                SizedBox(
                                  width: width,
                                  child: _EditorCard(
                                    kind: kind,
                                    enabled: !opening,
                                    onTap: () => open(
                                      kind,
                                      launch: const EditorLaunch(create: true),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                    ],
                    if (section != 3 || searching) ...[
                      Text(
                        searching
                            ? 'Результаты поиска'
                            : section == 2
                            ? 'Избранное'
                            : section == 1
                            ? 'Файлы на устройстве'
                            : 'Недавние файлы',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: opening ? null : chooseKind,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Открыть файл с устройства'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final k in <EditorKind?>[
                              null,
                              ...EditorKind.values,
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 52,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(
                                      k?.label ?? 'Все',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    selected: filter == k,
                                    onSelected: (_) =>
                                        setState(() => filter = k),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...fileWidgets(colors),
                      const SizedBox(height: 28),
                    ],
                    if (!searching) ...[
                      const Text(
                        'С чистого листа — или с шаблона',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final scale = MediaQuery.textScalerOf(context)
                              .scale(1);
                          final cols =
                              constraints.maxWidth >= 750 && scale < 1.4
                              ? 3
                              : 1;
                          final width =
                              (constraints.maxWidth - 12 * (cols - 1)) / cols;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final k in [
                                EditorKind.word,
                                EditorKind.excel,
                                EditorKind.slides,
                              ])
                                SizedBox(
                                  width: width,
                                  child: _TemplateCard(
                                    kind: k,
                                    enabled: !opening,
                                    onTap: () => open(
                                      k,
                                      launch: const EditorLaunch(
                                        create: true,
                                        template: true,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Локальные рабочие копии хранятся внутри приложения. '
                      'Исходники не перезаписываются; для переноса используйте «Сохранить копию».',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (store.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          store.error!,
                          style: TextStyle(fontSize: 14, color: colors.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide ? null : bottomNav(context),
    );
  }

  List<Widget> fileWidgets(ColorScheme colors) {
    final q = search.text.trim().toLowerCase();
    final list = store.files
        .where(
          (f) =>
              (filter == null || f.kind == filter) &&
              (section != 2 || f.favorite) &&
              f.name.toLowerCase().contains(q),
        )
        .toList();
    if (!store.loaded) {
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: LinearProgressIndicator(),
        ),
      ];
    }
    if (list.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                section == 2 ? Icons.star_border : Icons.folder_open_outlined,
                size: 36,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                q.isNotEmpty
                    ? 'Файлы не найдены'
                    : section == 2
                    ? 'Здесь будут избранные файлы'
                    : 'Ваш первый файл появится здесь',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                section == 2
                    ? 'Нажмите звёздочку рядом с нужным файлом.'
                    : 'Откройте документ с устройства или сохраните новый.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final file in list)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: opening ? null : () => open(file.kind, entry: file),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 4, 18),
                    child: Row(
                      children: [
                        FormatIcon(kind: file.kind),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${file.kind.format} · ${file.modified.day}.${file.modified.month} · рабочая копия',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: file.favorite ? 'Убрать из избранного' : 'В избранное',
                onPressed: () => favorite(file),
                icon: Icon(
                  file.favorite ? Icons.star : Icons.star_border,
                  color: file.favorite
                      ? const Color(0xffbc8b25)
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
    ];
  }

  IconData navIcon(int i) => [
    Icons.home_outlined,
    Icons.folder_outlined,
    Icons.star_border,
    Icons.dashboard_outlined,
  ][i];
  String navLabel(int i) => ['Главная', 'Файлы', 'Избранное', 'Шаблоны'][i];
  Widget bottomNav(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final i in [0, 1, -1, 2, 3])
                Expanded(
                  child: i == -1
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 4,
                          ),
                          child: IconButton.filled(
                            tooltip: 'Создать',
                            onPressed: opening
                                ? null
                                : () => chooseKind(create: true),
                            style: IconButton.styleFrom(
                              backgroundColor: OfficeTheme.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(52, 56),
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.add, size: 28),
                          ),
                        )
                      : Tooltip(
                          message: navLabel(i),
                          child: Semantics(
                            selected: section == i,
                            button: true,
                            child: InkWell(
                              onTap: () => selectSection(i),
                              borderRadius: BorderRadius.circular(12),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: scale > 1.3 ? 64 : 68,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 2,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        navIcon(i),
                                        color: section == i
                                            ? OfficeTheme.primary
                                            : colors.onSurfaceVariant,
                                        size: 26,
                                      ),
                                      if (scale <= 1.3) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          navLabel(i),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: section == i
                                                ? FontWeight.w600
                                                : null,
                                            color: section == i
                                                ? OfficeTheme.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
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

class FormatIcon extends StatelessWidget {
  const FormatIcon({super.key, required this.kind});
  final EditorKind kind;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 52,
    decoration: BoxDecoration(
      color: kind.tint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(kind.glyph, color: Colors.white, size: 28),
  );
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.kind,
    required this.onTap,
    required this.enabled,
  });
  final EditorKind kind;
  final VoidCallback onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: .13),
      ),
    ),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FormatIcon(kind: kind),
                const Spacer(),
                Icon(Icons.add, color: kind.tint),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              kind.label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              kind.description,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.kind,
    required this.onTap,
    required this.enabled,
  });
  final EditorKind kind;
  final VoidCallback onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final title = switch (kind) {
      EditorKind.word => 'План проекта',
      EditorKind.excel => 'Бюджет команды',
      _ => 'Презентация идеи',
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              FormatIcon(kind: kind),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${kind.format} · заготовка',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
