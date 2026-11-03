import 'dart:io';

import 'package:artofficecraft_mobile/main.dart';
import 'package:artofficecraft_mobile/ui/theme_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'draft_test_io.dart';

void main() {
  test(
    'Theme survives fresh instances and rapid changes keep the newest',
    () async {
      final dir = await Directory.systemTemp.createTemp('aoc-theme-');
      addTearDown(() => dir.delete(recursive: true));
      final settings = ThemeSettings(directory: dir);
      await Future.wait([
        settings.select(ThemeMode.dark),
        settings.select(ThemeMode.light),
        settings.select(ThemeMode.dark),
      ]);
      settings.dispose();
      final reopened = ThemeSettings(directory: dir);
      await reopened.load();
      expect(reopened.mode, ThemeMode.dark);
      await reopened.select(ThemeMode.light);
      final light = ThemeSettings(directory: dir);
      await light.load();
      expect(light.mode, ThemeMode.light);
      await File('${dir.path}/appearance.json').writeAsString('{broken');
      final damaged = ThemeSettings(directory: dir);
      await damaged.load();
      expect(damaged.mode, ThemeMode.light);
      reopened.dispose();
      light.dispose();
      damaged.dispose();
    },
  );
  test('A late load does not overwrite a newly selected theme', () async {
    final dir = await Directory.systemTemp.createTemp('aoc-theme-race-');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/appearance.json')
        .writeAsString('{"theme":"light"}');
    final settings = ThemeSettings(directory: dir);
    await Future.wait([settings.load(), settings.select(ThemeMode.dark)]);
    expect(settings.mode, ThemeMode.dark);
    final reopened = ThemeSettings(directory: dir);
    await reopened.load();
    expect(reopened.mode, ThemeMode.dark);
    settings.dispose();
    reopened.dispose();
  });
  testWidgets(
    'The saved theme is used on the first frame and a new app instance',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('aoc-theme-app-'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      const channel = MethodChannel('artofficecraft/workspace');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'directory' ? dir.path : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final initial = ThemeSettings(directory: dir);
      await waitDraftIO(tester, () async {
        await initial.select(ThemeMode.dark);
      });
      initial.dispose();
      final first = ThemeSettings(directory: dir);
      await waitDraftIO(tester, first.load);
      await tester.pumpWidget(
        ArtOfficeCraftApp(initialLanguage: 'ru', themeSettings: first),
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Изменить тему'));
      await waitDraftIO(tester, first.flush);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      final second = ThemeSettings(directory: dir);
      await waitDraftIO(tester, second.load);
      await tester.pumpWidget(
        ArtOfficeCraftApp(initialLanguage: 'ru', themeSettings: second),
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
