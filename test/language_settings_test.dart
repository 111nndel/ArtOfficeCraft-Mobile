import 'dart:io';

import 'package:artofficecraft_mobile/l10n/language_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Language preference survives restart and rapid choices keep the newest',
    () async {
      final dir = await Directory.systemTemp.createTemp('aoc-language-');
      addTearDown(() => dir.delete(recursive: true));
      final settings = LanguageSettings(directory: dir);
      await Future.wait([
        settings.select('en'),
        settings.select('ru'),
        settings.select('en'),
      ]);
      final loaded = LanguageSettings(directory: dir);
      await loaded.load();
      expect(loaded.language, 'en');
      await loaded.select('system');
      final system = LanguageSettings(directory: dir);
      await system.load();
      expect(system.locale, isNull);
      await File('${dir.path}/language.json').writeAsString('{broken');
      final damaged = LanguageSettings(directory: dir);
      await damaged.load();
      expect(damaged.language, 'system');
    },
  );
}
