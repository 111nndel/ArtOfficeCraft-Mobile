import 'package:artofficecraft_mobile/l10n/app_strings.dart';
import 'package:artofficecraft_mobile/main.dart';
import 'package:artofficecraft_mobile/ui/editor_tools.dart';
import 'package:artofficecraft_mobile/ui/office_tool_sections.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'loaded_editors_test.dart' show FakeDocumentBackend;

Widget englishApp(Widget child) => MaterialApp(locale: const Locale('en'),
  supportedLocales: const [Locale('en'), Locale('ru')],
  localizationsDelegates: const [AppStrings.delegate, ...GlobalMaterialLocalizations.delegates],
  home: child);
void main() {
  testWidgets('English Home, file menu and nested tool sections have English labels', (tester) async {
    await tester.pumpWidget(const ArtOfficeCraftApp(initialLanguage: 'en'));
    await tester.pumpAndSettle();
    expect(find.text('Spreadsheet'), findsOneWidget);
    expect(find.byTooltip('About and licenses'), findsOneWidget);
    final untranslated = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '')
      .where((s) => RegExp('[А-Яа-яЁё]').hasMatch(s));
    expect(untranslated, isEmpty);
    await tester.pumpWidget(englishApp(Scaffold(bottomNavigationBar: EditorToolPanel(
      sections: officeSections('grid'), color: Colors.green))));
    await tester.tap(find.byKey(const Key('tool-section-caption'))); await tester.pumpAndSettle();
    expect(find.text('Formulas'), findsOneWidget);
    await tester.tap(find.text('View')); await tester.pumpAndSettle();
    expect(find.text('Freeze panes'), findsOneWidget);
    expect(find.text('Not implemented yet'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('English UI preserves Russian document names, content, cell input and sheet names', (tester) async {
    final word = FakeDocumentBackend(NativeDocumentKind.word)..text = 'Главная';
    await tester.pumpWidget(englishApp(NativeWordScreen(backend: word,
      launch: EditorLaunch(bytes: word.bytes(), name: 'Документ.docx'))));
    await tester.pumpAndSettle();
    expect(find.text('Документ.docx'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    final grid = FakeDocumentBackend(NativeDocumentKind.grid);
    await tester.pumpWidget(englishApp(NativeGridScreen(backend: grid,
      launch: EditorLaunch(bytes: grid.bytes(), name: 'Моя таблица.xlsx'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('grid-cell-A1'))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Заливка'); await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Заливка');
    expect(find.text('Лист 1'), findsOneWidget);
    expect(grid.calls, 0);
  });
  test('All four tool catalogs have English translations without changing command IDs', () {
    const strings = AppStrings(Locale('en'));
    for (final kind in officeToolLabels.values) {
      for (final entry in kind.entries) {
        expect(strings.translate(entry.key), isNot(entry.key));
        for (final tool in entry.value) {
          expect(RegExp('[А-Яа-яЁё]').hasMatch(strings.translate(tool)), isFalse, reason: tool);
        }
      }
    }
    expect(strings.translate('Несохранённый ввод «Главная» будет удалён. Исходный файл останется на месте.'), contains('“Главная”'));
  });
}
