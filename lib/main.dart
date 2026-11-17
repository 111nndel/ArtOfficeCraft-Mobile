import 'native/grid_clipboard.dart';
import 'platform/application_storage.dart';
import 'platform/document_files.dart';
import 'native/pdf_page_renderer.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'l10n/language_settings.dart';

import 'ui/home_screen.dart';
import 'ui/office_theme.dart';
import 'ui/project_info_screen.dart';
import 'ui/theme_settings.dart';
import 'updates/app_updates.dart';

export 'ui/home_screen.dart' show HomeScreen;
export 'workspace/editor_kind.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerRustLicenses();
  final appearance = ThemeSettings();
  await appearance.load();
  runApp(ArtOfficeCraftApp(themeSettings: appearance));
}

class ArtOfficeCraftApp extends StatefulWidget {
  const ArtOfficeCraftApp({
    super.key,
    this.initialLanguage,
    this.themeSettings,
    this.storage = const AndroidApplicationStorage(),
    this.files = const MobileDocumentFiles(),
    this.pdfRenderer,
    this.clipboard,
    this.updates,
  });
  final String? initialLanguage;
  final ApplicationStorage storage;
  final DocumentFiles files;
  final PdfPageRenderer? pdfRenderer;
  final GridClipboard? clipboard;
  final AppUpdates? updates;

  /// Owned by the app; main supplies an already loaded preference before paint.
  final ThemeSettings? themeSettings;
  @override
  State<ArtOfficeCraftApp> createState() => _ArtOfficeCraftAppState();
}

class _ArtOfficeCraftAppState extends State<ArtOfficeCraftApp>
    with WidgetsBindingObserver {
  late final appearance =
      widget.themeSettings ?? ThemeSettings(storage: widget.storage);
  final messenger = GlobalKey<ScaffoldMessengerState>();
  final navigator = GlobalKey<NavigatorState>();
  late final updates = widget.updates ?? AppUpdates(storage: widget.storage);
  int? _notifiedUpdate;
  late final settings = LanguageSettings(
    storage: widget.storage,
    initial: widget.initialLanguage ?? 'system',
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    updates.addListener(_updateReady);
    if (widget.updates == null) unawaited(updates.load());
    if (widget.themeSettings == null) unawaited(appearance.load());
    if (widget.initialLanguage == null) unawaited(settings.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updates.removeListener(_updateReady);
    if (widget.updates == null) updates.dispose();
    settings.dispose();
    appearance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(updates.automaticCheck());
  }

  void _updateReady() {
    if (updates.phase != UpdatePhase.ready ||
        updates.release?.code == _notifiedUpdate) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          updates.phase != UpdatePhase.ready ||
          updates.release?.code == _notifiedUpdate) {
        return;
      }
      final context = navigator.currentContext;
      if (context == null) return;
      _notifiedUpdate = updates.release!.code;
      messenger.currentState?.showSnackBar(
        SnackBar(
          content: const UiText('Обновление готово к установке'),
          duration: const Duration(seconds: 8),
          persist: false,
          showCloseIcon: true,
          action: SnackBarAction(
            label: tr(context, 'Открыть'),
            onPressed: () {
              navigator.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (_) => ProjectInfoScreen(updates: updates),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([settings, appearance]),
    builder: (context, _) => LanguageScope(
      settings: settings,
      child: MaterialApp(
        scaffoldMessengerKey: messenger,
        navigatorKey: navigator,
        locale: settings.locale,
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        debugShowCheckedModeBanner: false,
        title: 'ArtOfficeCraft Mobile',
        themeMode: appearance.mode,
        theme: OfficeTheme.build(Brightness.light),
        darkTheme: OfficeTheme.build(Brightness.dark),
        home: HomeScreen(
          updates: updates,
          storage: widget.storage,
          files: widget.files,
          pdfRenderer: widget.pdfRenderer,
          clipboard: widget.clipboard,
          theme: appearance.mode,
          toggleTheme: () async {
            final saved = await appearance.select(
              appearance.mode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            );
            if (!saved && mounted) {
              messenger.currentState?.showSnackBar(
                const SnackBar(
                  content: UiText(
                    'Не удалось сохранить тему. Повторите выбор.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    ),
  );
}
