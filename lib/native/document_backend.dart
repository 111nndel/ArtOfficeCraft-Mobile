import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'wordcraft_bridge.dart';
import 'gridcraft_bridge.dart';
import 'deckcraft_bridge.dart';
import 'pdfcraft_bridge.dart';

enum NativeDocumentKind { word, grid, deck, pdf }

/// Injectable asynchronous boundary: widgets never parse files or call Rust FFI.
abstract interface class DocumentBackend {
  Future<Uint8List> create([String text = '']);
  Future<Map<String, dynamic>> inspect(Uint8List bytes);
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request);
}

final class NativeDocumentBackend implements DocumentBackend {
  const NativeDocumentBackend(this.kind, {this.libraryPath});
  final NativeDocumentKind kind;
  final String? libraryPath;

  static DocumentBackend? tryOpen(NativeDocumentKind kind) {
    if (!Platform.isAndroid) return null;
    try {
      // Loading symbols is cheap; parsing, formatting and serialization run below.
      ffi.DynamicLibrary.open('libartoffice_core.so');
      return NativeDocumentBackend(kind);
    } catch (_) {
      return null;
    }
  }

  Future<Object> _call(
    String operation,
    Uint8List? bytes,
    Map<String, dynamic> request,
  ) {
    // Capture transferable values, never a DynamicLibrary or a widget State.
    final kind = this.kind;
    final path = libraryPath;
    return Isolate.run(
      () => _nativeCall(kind, path, operation, bytes, request),
    );
  }

  @override
  Future<Uint8List> create([String text = '']) async =>
      await _call('create', null, {'text': text}) as Uint8List;
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async =>
      Map<String, dynamic>.from(await _call('inspect', bytes, {}) as Map);
  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async =>
      await _call('edit', bytes, request) as Uint8List;
}

Object _nativeCall(
  NativeDocumentKind kind,
  String? library,
  String operation,
  Uint8List? bytes,
  Map<String, dynamic> request,
) {
  switch (kind) {
    case NativeDocumentKind.word:
      final engine = library == null
          ? WordCraftBridge.tryOpen()
          : WordCraftBridge.openLibraryForTesting(library);
      if (engine == null) {
        throw StateError('WordCraft недоступен в этой сборке');
      }
      if (operation == 'create') {
        return engine.create(request['text'] as String? ?? '');
      }
      if (operation == 'inspect') return engine.inspect(bytes!);
      if (request['action'] == 'append') {
        return engine.appendParagraph(bytes!, request['text'] as String);
      }
      return engine.edit(bytes!, request);
    case NativeDocumentKind.grid:
      final engine = library == null
          ? GridCraftBridge.tryOpen()
          : GridCraftBridge.openLibraryForTesting(library);
      if (engine == null) {
        throw StateError('GridCraft недоступен в этой сборке');
      }
      if (operation == 'create') return engine.create();
      if (operation == 'inspect') return engine.inspect(bytes!);
      return engine.edit(bytes!, request);
    case NativeDocumentKind.deck:
      final engine = library == null
          ? DeckCraftBridge.tryOpen()
          : DeckCraftBridge.openLibraryForTesting(library);
      if (engine == null) {
        throw StateError('DeckCraft недоступен в этой сборке');
      }
      if (operation == 'create') return engine.create();
      if (operation == 'inspect') return engine.inspect(bytes!);
      return engine.edit(bytes!, request);
    case NativeDocumentKind.pdf:
      final engine = library == null
          ? PdfCraftBridge.tryOpen()
          : PdfCraftBridge.openLibraryForTesting(library);
      if (engine == null) throw StateError('PdfCraft недоступен в этой сборке');
      if (operation == 'create') return engine.create();
      if (operation == 'inspect') return engine.inspect(bytes!);
      return engine.edit(bytes!, request);
  }
}
