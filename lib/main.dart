import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/office_theme.dart';

export 'ui/home_screen.dart' show HomeScreen;
export 'workspace/editor_kind.dart';

void main() => runApp(const ArtOfficeCraftApp());

class ArtOfficeCraftApp extends StatefulWidget {
  const ArtOfficeCraftApp({super.key});
  @override
  State<ArtOfficeCraftApp> createState() => _ArtOfficeCraftAppState();
}

class _ArtOfficeCraftAppState extends State<ArtOfficeCraftApp> {
  ThemeMode theme = ThemeMode.light;
  @override
  Widget build(BuildContext context) => MaterialApp(
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
  );
}
