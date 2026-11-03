import 'dart:io';

import 'package:artofficecraft_mobile/ui/home_screen.dart';
import 'package:artofficecraft_mobile/ui/office_theme.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/workspace_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Recovery is visible on Home; deleting it confirms and preserves the workspace copy',(tester)async {
    final dir=await Directory.systemTemp.createTemp('aoc-home-draft-');addTearDown(()=>dir.delete(recursive:true));
    final workspace=WorkspaceStore(directory:await Directory('${dir.path}/files').create());await workspace.load();
    final original=await workspace.remember(EditorKind.word,Uint8List.fromList([1,2,3]),'Проект.docx');
    final drafts=DraftStore(directory:Directory('${dir.path}/drafts'));await drafts.load();
    final info=await drafts.write(id:'r0123456789abcdef0123456789abcdef',kind:EditorKind.word,name:'Проект.docx',bytes:Uint8List.fromList([4,5]),editor:{'text':'Черновик'});
    tester.view.physicalSize=const Size(393,873);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:OfficeTheme.build(Brightness.light),home:HomeScreen(toggleTheme:(){},theme:ThemeMode.light,workspace:workspace,drafts:drafts)));
    await tester.pumpAndSettle();
    expect(find.text('Восстановить работу'),findsOneWidget);expect(find.byKey(ValueKey('recovery-${info.id}')),findsOneWidget);
    await tester.tap(find.byTooltip('Действия с черновиком'));await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить черновик'));await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));await tester.pumpAndSettle();expect(drafts.items,hasLength(1));
    await tester.tap(find.byTooltip('Действия с черновиком'));await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить черновик'));await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));await tester.pumpAndSettle();await tester.runAsync(drafts.load);await tester.pump();
    expect(drafts.items,isEmpty);expect(await workspace.read(original),[1,2,3]);expect(tester.takeException(),isNull);
  });
}
