# Обновление Rust-ядер ArtOfficeCraft Mobile

## Назначение

Проект автоматически **проверяет опубликованные стабильные версии исходников** WordCraft, GridCraft, DeckCraft и PDFCraft на официальном GitHub. Новые исходники загружаются только в отдельную папку и не изменяют приложение до проверки совместимости. Утверждённый UI сохраняется.

В `upstream/engines.lock.json` зафиксированы не только версии, но и полные SHA коммитов. Движки допускаются из четырёх перечисленных репозиториев, теги сверяются с GitHub, а версия Cargo.toml сверяется с тегом.

## Для использования на компьютере

В папке `корне скачанного репозитория ArtOfficeCraft-Mobile` доступны:
- `check-rust-engines.ps1` — проверяет новые версии всех 4 движков. Отчёт: `upstream/reports/latest-check.json`.
- `stage-rust-engines.ps1` — скачивает из GitHub закреплённые версии (без изменений рабочей программы).
- `stage-rust-engines.ps1 -Latest` — скачивает последние опубликованные стабильные релизы в изолированную папку `upstream/staged`.

Из PowerShell их можно запускать командой `powershell -ExecutionPolicy Bypass -File .\check-rust-engines.ps1` (из папки проекта).

Продвинутая команда `python tools\engine_updater.py pin --engine wordcraft --tag v0.15.0 --ack-review` **только закрепляет ранее скачанную и проверенную версию исходников**, не собирает APK. Тег в примере условный. При закреплении предыдущий конфигурационный файл сохраняется в `upstream/lock-history` для отката. История локальная; её не нужно удалять.

## Политика безопасности и совместимости

1. Проверяем официальный GitHub и SHA, запрещаем неизвестные источники и предварительные версии.
2. Скачиваем в `upstream/staged/<engine>/<tag>-<sha>`; не меняем оригинальные ZIP-архивы и существующие проекты.
3. Читаем изменения, лицензии, зависимости; сверяем API/ABI Rust и FFI.
4. Собираем Rust под Android ARM64 через NDK, затем Flutter APK; тестируем DOCX/XLSX/PPTX/PDF, сохранение и повторное открытие.
5. Подписываем новый APK и распространяем обновление целиком.

**Сейчас Rust-движки ещё НЕ интегрированы в Android-приложение.** Подготовка загрузчика исходников не обеспечивает работу офисных функций сама по себе. Не будем загружать и запускать скачанные `.so` непосредственно в установленном приложении; для Google Play запрещено скачивать исполняемый код извне магазина: https://support.google.com/googleplay/android-developer/answer/16559646 .

Офисные операции внутри готового Android-приложения будут работать без интернета. GitHub нужен только машине сборки для проверки и получения исходников.

## Автоматизация

GitHub Actions workflow is not published in this initial commit because the connected GitHub CLI has no workflow write permission. Weekly hosted checks can be enabled later with a separately reviewed permission grant. Local source checking and staging remain available.

ArtCraft и Craft Launcher в этот механизм не входят: ArtCraft имеет другую цель и ограничения лицензии.
