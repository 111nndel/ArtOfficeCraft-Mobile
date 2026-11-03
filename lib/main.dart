import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'l10n/language_settings.dart';

import 'ui/home_screen.dart';
import 'ui/office_theme.dart';
import 'ui/project_info_screen.dart';
import 'ui/theme_settings.dart';

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
  });
  final String? initialLanguage;

  /// Owned by the app; main supplies an already loaded preference before paint.
  final ThemeSettings? themeSettings;
  @override
  State<ArtOfficeCraftApp> createState() => _ArtOfficeCraftAppState();
}

class _ArtOfficeCraftAppState extends State<ArtOfficeCraftApp> {
  late final appearance = widget.themeSettings ?? ThemeSettings();
  final messenger = GlobalKey<ScaffoldMessengerState>();
  late final settings = LanguageSettings(
    initial: widget.initialLanguage ?? 'system',
  );
  @override
  void initState() {
    super.initState();
    if (widget.themeSettings == null) unawaited(appearance.load());
    if (widget.initialLanguage == null) unawaited(settings.load());
  }

  @override
  void dispose() {
    settings.dispose();
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([settings, appearance]),
    builder: (context, _) => LanguageScope(
      settings: settings,
      child: MaterialApp(
        scaffoldMessengerKey: messenger,
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
