import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'l10n/language_settings.dart';

import 'ui/home_screen.dart';
import 'ui/office_theme.dart';
import 'ui/project_info_screen.dart';

export 'ui/home_screen.dart' show HomeScreen;
export 'workspace/editor_kind.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerRustLicenses();
  runApp(const ArtOfficeCraftApp());
}

class ArtOfficeCraftApp extends StatefulWidget {
  const ArtOfficeCraftApp({super.key, this.initialLanguage});
  final String? initialLanguage;
  @override
  State<ArtOfficeCraftApp> createState() => _ArtOfficeCraftAppState();
}

class _ArtOfficeCraftAppState extends State<ArtOfficeCraftApp> {
  ThemeMode theme = ThemeMode.light;
  late final settings = LanguageSettings(
    initial: widget.initialLanguage ?? 'system',
  );
  @override
  void initState() {
    super.initState();
    if (widget.initialLanguage == null) unawaited(settings.load());
  }

  @override
  void dispose() {
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => LanguageScope(
      settings: settings,
      child: MaterialApp(
        locale: settings.locale,
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        debugShowCheckedModeBanner: false,
        title: 'ArtOfficeCraft Mobile',
        themeMode: theme,
        theme: OfficeTheme.build(Brightness.light),
        darkTheme: OfficeTheme.build(Brightness.dark),
        home: HomeScreen(
          theme: theme,
          toggleTheme: () => setState(() {
            theme = theme == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          }),
        ),
      ),
    ),
  );
}
