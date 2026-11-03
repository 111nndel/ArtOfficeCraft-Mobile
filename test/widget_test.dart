import 'package:flutter_test/flutter_test.dart';
import 'package:artofficecraft_mobile/main.dart';

void main() {
  testWidgets('Home shows four editors and opens spreadsheet', (tester) async {
    await tester.pumpWidget(const ArtOfficeCraftApp());
    expect(find.text('ArtOfficeCraft'), findsOneWidget);
    expect(find.text('Таблица'), findsOneWidget);
    await tester.tap(find.text('Таблица'));
    await tester.pumpAndSettle();
    expect(find.text('Книга.xlsx'), findsOneWidget);
    expect(find.text('Rust недоступен'), findsOneWidget);
    expect(find.byTooltip('Меню файла'), findsOneWidget);
  });
}
