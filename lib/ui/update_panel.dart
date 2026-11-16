import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../updates/app_updates.dart';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, required this.updates});
  final AppUpdates updates;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      final release = updates.release;
      final supported = updates.installed?.abi == 'arm64-v8a';
      final status = switch (updates.phase) {
        UpdatePhase.checking => 'Проверяем обновления…',
        UpdatePhase.available => 'Доступна версия ${release?.version}',
        UpdatePhase.downloading =>
          'Скачивание: ${release == null ? 0 : (updates.received * 100 ~/ release.size)}%',
        UpdatePhase.ready => 'Версия ${release?.version} готова к установке',
        UpdatePhase.failed => 'Не удалось проверить или скачать обновление. Повторите попытку позже.',
        UpdatePhase.idle =>
          updates.checked
              ? 'Установлена актуальная версия.'
              : 'Обновления с GitHub Releases',
      };
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const UiText(
                'Обновления приложения',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Semantics(
                container: true,
                child: DropdownButtonFormField<bool>(
                  key: ValueKey(('update-mode', updates.automatic)),
                  initialValue: updates.automatic,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Режим обновления'),
                  ),
                  items: const [
                    DropdownMenuItem(value: false, child: UiText('Вручную')),
                    DropdownMenuItem(
                      value: true,
                      child: UiText('Автоматически'),
                    ),
                  ],
                  onChanged: !updates.loaded || updates.installing
                      ? null
                      : (value) {
                          if (value != null) updates.selectAutomatic(value);
                        },
                ),
              ),
              const SizedBox(height: 12),
              UiText(
                updates.automatic
                    ? 'Проверка и скачивание при запуске и возврате в приложение, не чаще раза в сутки.'
                    : 'Приложение обращается к GitHub только по кнопке проверки или скачивания.',
              ),
              const SizedBox(height: 12),
              Semantics(
                container: true,
                child: UiText(status, key: const Key('update-status')),
              ),
              if (!supported && updates.loaded)
                const UiText('APK-обновления доступны для Android ARM64.'),
              if (updates.preferenceError)
                const UiText(
                  'Не удалось сохранить режим обновления. Выбор действует до закрытия приложения.',
                ),
              if (updates.busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value:
                      updates.phase == UpdatePhase.downloading &&
                          release != null
                      ? updates.received / release.size
                      : null,
                ),
                TextButton(
                  onPressed: updates.cancel,
                  child: const UiText('Отмена'),
                ),
              ] else ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('check-app-update'),
                  onPressed: updates.loaded && supported && !updates.installing
                      ? updates.check
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const UiText('Проверить обновления'),
                ),
                if (release != null && supported)
                  FilledButton.icon(
                    key: const Key('download-app-update'),
                    onPressed: updates.installing
                        ? null
                        : updates.phase == UpdatePhase.ready
                        ? () async {
                            final opened = await updates.install();
                            if (!opened &&
                                context.mounted &&
                                updates.phase == UpdatePhase.ready) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: UiText(
                                    'Разрешите установку из ArtOfficeCraft в настройках Android, затем нажмите «Установить» ещё раз.',
                                  ),
                                ),
                              );
                            }
                          }
                        : updates.download,
                    icon: Icon(
                      updates.phase == UpdatePhase.ready
                          ? Icons.system_update
                          : Icons.download,
                    ),
                    label: UiText(
                      updates.phase == UpdatePhase.ready
                          ? 'Установить'
                          : 'Скачать обновление',
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const UiText(
                'Установка подтверждается в системном окне Android. Документы обрабатываются локально и не отправляются на сервер.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
