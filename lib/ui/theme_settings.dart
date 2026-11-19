import 'package:flutter/material.dart';

import '../platform/stored_choice.dart';

class ThemeSettings extends StoredChoice<ThemeMode> {
  ThemeSettings({
    super.directory,
    ThemeMode mode = ThemeMode.light,
    super.storage,
  }) : super(
         initial: mode,
         fileName: 'appearance.json',
         field: 'theme',
         options: {for (final mode in ThemeMode.values) mode.name: mode},
       );

  ThemeMode get mode => value;
}
