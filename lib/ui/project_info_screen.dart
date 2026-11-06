import '../l10n/app_strings.dart';

import 'dart:convert';

import '../l10n/language_settings.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../native/native_build_info.dart';

void registerRustLicenses() {
  LicenseRegistry.addLicense(() async* {
    final entries = jsonDecode(
      await rootBundle.loadString('assets/legal/rust-licenses.json'),
    ) as List;
    for (final entry in entries) {
      yield LicenseEntryWithLineBreaks(
        ['${entry['name']} ${entry['version']}'],
        (entry['texts'] as List).map((t) => t['text'].toString()).join('\n\n'),
      );
    }
  });
}

class ProjectInfoScreen extends StatefulWidget {
  const ProjectInfoScreen({super.key});
  @override
  State<ProjectInfoScreen> createState() => _ProjectInfoScreenState();
}

class _ProjectInfoScreenState extends State<ProjectInfoScreen> {
  late final Future<Map<String, dynamic>?> info = readNativeBuildInfo();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const UiText('О проекте и движках')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const UiText(
          'ArtOfficeCraft Mobile',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const UiText('0.36.0 · тестовая версия'),
        const SizedBox(height: 20),
        if (LanguageScope.maybeOf(context) case final settings?)
          DropdownButtonFormField<String>(
            key: const Key('app-language'),
            initialValue: settings.language,
            decoration: InputDecoration(
              labelText: tr(context, 'Язык / Language'),
            ),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: UiText('Системный язык'),
              ),
              DropdownMenuItem(value: 'ru', child: Text('Русский')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              final saved = await settings.select(value);
              if (!saved && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: UiText(
                      'Язык изменён только для этого сеанса: настройку не удалось сохранить.',
                    ),
                  ),
                );
              }
            },
          ),
        const UiText(
          'Независимый Android-порт с использованием четырёх открытых движков. '
          'Возможности мобильных редакторов пока ограничены. Полная совместимость с настольными приложениями не заявляется.',
        ),
        const SizedBox(height: 20),
        const UiSelectableText(
          'Исходники:\nhttps://github.com/111nndel/ArtOfficeCraft-Mobile',
        ),
        const SizedBox(height: 20),
        FutureBuilder<Map<String, dynamic>?>(
          future: info,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const UiText(
                'Не удалось прочитать версии нативных движков этой сборки.',
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            final data = snapshot.data;
            if (data == null) {
              return const UiText('Движки доступны в Android-сборке.');
            }
            final engines = data['engines'] as Map? ?? {};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UiText(
                  'Нативное ядро ${data['coreVersion']} · ABI ${data['abi']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final entry in engines.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: UiSelectableText(
                      '${entry.key} ${entry.value['tag']}\n${entry.value['commit']}\n${entry.value['repo']}',
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'ArtOfficeCraft Mobile',
            applicationVersion: '0.36.0',
          ),
          icon: const Icon(Icons.description_outlined),
          label: const UiText('Лицензии и авторские права'),
        ),
        const SizedBox(height: 20),
        const UiText(
          'Обновления движков проверяются по исходным репозиториям и точным коммитам. '
          'Приложение не скачивает и не запускает новые нативные библиотеки из интернета.',
        ),
      ],
    ),
  );
}
