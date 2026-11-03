import 'dart:io';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_word_screen.dart';
import 'package:artofficecraft_mobile/native/native_grid_screen.dart';
import 'package:artofficecraft_mobile/native/native_deck_screen.dart';
import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:artofficecraft_mobile/workspace/editor_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loaded_editors_test.dart' show FakeDocumentBackend,setup;
import 'grid_editing_test.dart' show MemoryGrid;

void main() {
  for(final kind in [EditorKind.word,EditorKind.excel,EditorKind.slides]) {
    testWidgets('$kind restores unapplied text from disk without native edits',(tester)async {
      final dir=await Directory.systemTemp.createTemp('aoc-editor-recovery-');
      addTearDown(()=>dir.delete(recursive:true));
      final store=DraftStore(directory:dir);final session=DraftSession(store,kind);
      final DocumentBackend backend=kind==EditorKind.excel ? MemoryGrid() : FakeDocumentBackend(kind==EditorKind.word ? NativeDocumentKind.word : NativeDocumentKind.deck);
      Widget screen(EditorLaunch launch,DraftSession draft)=>switch(kind) {
        EditorKind.word=>NativeWordScreen(backend:backend,launch:launch,draft:draft),
        EditorKind.excel=>NativeGridScreen(backend:backend,launch:launch,draft:draft),
        _=>NativeDeckScreen(backend:backend,launch:launch,draft:draft),
      };
      await setup(tester,const Size(393,873),1,screen(const EditorLaunch(create:true),session));
      if(kind==EditorKind.word) {await tester.tap(find.text('Проверяемый абзац'));await tester.pumpAndSettle();}
      if(kind==EditorKind.slides) {await tester.tap(find.text('Проверяемый абзац').first);await tester.pumpAndSettle();}
      final input=kind==EditorKind.word ? find.byKey(const Key('word-inline-input')) : kind==EditorKind.slides ? find.byKey(const Key('deck-text-input')) : find.byType(TextField);
      await tester.enterText(input,'Не применено 😀');await tester.pump();
      await tester.runAsync(()=>session.flush());
      await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(()=>session.close());
      final reopened=DraftStore(directory:dir);await tester.runAsync(reopened.load);
      final recovered=await tester.runAsync(()=>reopened.read(reopened.items.single.id));
      final resumed=DraftSession(reopened,kind,id:recovered!.info.id);
      await setup(tester,const Size(393,873),1,screen(EditorLaunch(bytes:recovered.bytes,name:recovered.info.name,recovery:recovered.editor),resumed));
      expect(tester.widget<TextField>(input).controller!.text,'Не применено 😀');
      if(backend is FakeDocumentBackend) expect(backend.calls,0);
      if(backend is MemoryGrid) expect(backend.requests,isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(()=>resumed.close());
      expect(tester.takeException(),isNull);
    });
  }
  testWidgets('Canceling Save As retains recovery; successful export clears it',(tester)async {
    final dir=await Directory.systemTemp.createTemp('aoc-recovery-save-');addTearDown(()=>dir.delete(recursive:true));
    final store=DraftStore(directory:dir);final session=DraftSession(store,EditorKind.excel);
    var canceled=true;
    const channel=MethodChannel('flutter_file_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(_)async=>canceled ? null : '/test/book.xlsx');
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));
    await setup(tester,const Size(393,873),1,NativeGridScreen(backend:MemoryGrid(),draft:session,launch:const EditorLaunch(create:true)));
    await tester.enterText(find.byType(TextField),'42');await tester.pump();await tester.runAsync(()=>session.flush());
    Future<void> save()async {await tester.tap(find.byTooltip('Меню файла'));await tester.pumpAndSettle();await tester.tap(find.text('Сохранить копию'));await tester.pumpAndSettle();await tester.runAsync(()=>session.flush());}
    await save();expect(store.items,hasLength(1));canceled=false;await save();expect(store.items,isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(()=>session.close());expect(tester.takeException(),isNull);
  });
}
