import 'package:flutter/material.dart';

import '../platform/stored_choice.dart';

class LanguageSettings extends StoredChoice<String> {
  LanguageSettings({super.directory, String initial = 'system', super.storage})
    : super(
        initial: initial,
        fileName: 'language.json',
        field: 'language',
        options: {for (final code in choices) code: code},
      );

  static const choices = ['system', 'ru', 'en'];
  String get language => value;
  Locale? get locale => language == 'system' ? null : Locale(language);
}

class LanguageScope extends InheritedNotifier<LanguageSettings> {
  const LanguageScope({
    super.key,
    required LanguageSettings settings,
    required super.child,
  }) : super(notifier: settings);
  static LanguageSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
}
