import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/workspace/draft_store.dart';
import 'package:artofficecraft_mobile/workspace/editor_kind.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class DelayedFailureStore extends DraftStore {
  DelayedFailureStore(Directory directory):super(directory:directory);
  final gate=Completer<void>();
  int writes=0;
  @override
  Future<DraftInfo> write({required String id,required EditorKind kind,required String name,required Uint8List bytes,required Map<String,dynamic> editor,String? workspaceId,String? reuseBase}) async {
    if(++writes==1) {await gate.future;throw const FileSystemException('Delayed first write failure');}
    return super.write(id:id,kind:kind,name:name,bytes:bytes,editor:editor,workspaceId:workspaceId,reuseBase:reuseBase);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {root=await Directory.systemTemp.createTemp('aoc-draft-test-');});
  tearDown(()async {await root.delete(recursive:true);});
  final base=Uint8List.fromList([80,75,3,4,1]);
  const id='r0123456789abcdef0123456789abcdef';
  test('Raw input, selected position and base survive a fresh store; typing reuses the base',()async {
    final store=DraftStore(directory:root);
    final first=await store.write(id:id,kind:EditorKind.word,name:'Проект.docx',bytes:base,editor:{'text':'Не применено 😀','activeBlock':0});
    await store.write(id:id,kind:EditorKind.word,name:'Проект.docx',bytes:base,reuseBase:first.base,editor:{'text':'Ещё ввод 😀','activeBlock':0});
    final next=DraftStore(directory:root);await next.load();
    final recovered=await next.read(next.items.single.id);
    expect(recovered.bytes,orderedEquals(base));expect(recovered.editor['text'],'Ещё ввод 😀');
    expect(root.listSync().where((f)=>f.path.endsWith('.bin')),hasLength(1));
    expect(recovered.info.name,'Проект.docx');
  });
  test('Incomplete replacement files cannot replace the last durable checkpoint',()async {
    final store=DraftStore(directory:root);
    final info=await store.write(id:id,kind:EditorKind.excel,name:'Книга.xlsx',bytes:base,editor:{'selected':'C15','input':'12,5'});
    await File('${root.path}/$id.json.tmp').writeAsString('{incomplete');
    await File('${root.path}/$id-b1111111111111111.bin.tmp').writeAsBytes([9]);
    final next=DraftStore(directory:root);await next.load();
    expect(next.items.single.base,info.base);expect((await next.read(id)).editor['input'],'12,5');
    await next.write(id:id,kind:EditorKind.excel,name:'Книга.xlsx',bytes:Uint8List.fromList([9,8]),editor:{'input':'13'});
    expect(root.listSync().where((f)=>f.path.endsWith('.bin')),hasLength(1));
  });
  test('Corrupt or path-traversal records stay intact and do not hide valid recovery',()async {
    final store=DraftStore(directory:root);
    final info=await store.write(id:id,kind:EditorKind.pdf,name:'PDF.pdf',bytes:base,editor:{'page':1});
    const invalid='rffffffffffffffffffffffffffffffff';
    await File('${root.path}/$invalid.json').writeAsString(jsonEncode({'schema':1,'id':invalid,'base':'../../private','name':'bad','kind':'pdf','modified':DateTime.now().toIso8601String()}));
    final next=DraftStore(directory:root);await next.load();
    expect(next.items.single.id,info.id);expect(next.error,isNotNull);
    expect(await File('${root.path}/$invalid.json').exists(),isTrue);
    await expectLater(next.read('../outside'),throwsFormatException);
  });
  test('Newest queued input wins; an explicit discard cannot resurrect a draft',()async {
    final store=DraftStore(directory:root);
    final session=DraftSession(store,EditorKind.word,delay:const Duration(days:1));
    session.update(bytes:base,name:'A.docx',editor:{'text':'old'},dirty:true);
    final old=session.flush();
    session.update(bytes:base,name:'A.docx',editor:{'text':'new'},dirty:true);
    await session.flush();await old;
    expect((await store.read(session.id)).editor['text'],'new');
    session.update(bytes:base,name:'A.docx',editor:{'text':'must retire'},dirty:true);
    final writing=session.flush();await session.discard();await writing;
    session.update(bytes:base,name:'A.docx',editor:{'text':'late callback'},dirty:true);
    await session.close();final next=DraftStore(directory:root);await next.load();
    expect(next.items,isEmpty);expect(root.listSync(),isEmpty);
  });
  test('An older failed write cannot replace a newer queued checkpoint',()async {
    final store=DelayedFailureStore(root);final session=DraftSession(store,EditorKind.word,delay:const Duration(days:1));
    session.update(bytes:base,name:'A.docx',editor:{'text':'old'},dirty:true);final old=session.flush();
    await Future<void>.delayed(Duration.zero);
    session.update(bytes:base,name:'A.docx',editor:{'text':'latest'},dirty:true);final latest=session.flush();
    store.gate.complete();await old;await latest;await session.close();
    expect((await store.read(session.id)).editor['text'],'latest');expect(store.writes,2);
  });
  test('App pause flushes pending input and a successful save retires the journal',()async {
    final store=DraftStore(directory:root);final session=DraftSession(store,EditorKind.slides,delay:const Duration(days:1));
    session.update(bytes:base,name:'P.pptx',editor:{'text':'Черновик'},dirty:true);
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    await session.flush();expect((await store.read(session.id)).editor['text'],'Черновик');
    session.update(bytes:base,name:'P.pptx',editor:{},dirty:false);
    await session.close();final next=DraftStore(directory:root);await next.load();expect(next.items,isEmpty);
  });
  test('A failed manifest replacement retains the prior snapshot and can be retried',()async {
    final store=DraftStore(directory:root);final session=DraftSession(store,EditorKind.excel,delay:const Duration(days:1));
    session.update(bytes:base,name:'B.xlsx',editor:{'input':'last durable'},dirty:true);await session.flush();
    // A directory at the temporary manifest path deterministically blocks the write.
    final blocker=await Directory('${root.path}/${session.id}.json.tmp').create();
    session.update(bytes:Uint8List.fromList([7,7]),name:'B.xlsx',editor:{'input':'latest'},dirty:true);await session.flush();
    expect((await store.read(session.id)).editor['input'],'last durable');expect(session.status,contains('не записан'));
    await blocker.delete();await session.flush();expect((await store.read(session.id)).editor['input'],'latest');await session.close();
  });
}
