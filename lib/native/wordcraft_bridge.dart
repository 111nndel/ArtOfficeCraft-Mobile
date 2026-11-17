import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'native_core_library.dart';

/// WordCraft native adapter. No document data is sent over the network.
///
/// All Rust allocated buffers are freed even when decoding throws.
/// This low-level API is synchronous. UI screens use DocumentBackend to call it
/// in worker isolates; errors propagate without replacing the current document.
final class WordCraftBridge {
  WordCraftBridge._(ffi.DynamicLibrary library)
    : _inspect = library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_docx_inspect',
      ),
      _create = library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_docx_create',
      ),
      _append = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_docx_append_paragraph',
      ),
      _edit = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_docx_edit',
      ),
      _memory = NativeCoreMemory(library);
  final DartCoreOne _inspect;
  final DartCoreOne _create;
  final DartCoreTwo _append;
  final DartCoreTwo _edit;
  final NativeCoreMemory _memory;

  /// Native smoke tests may inject a compiled library explicitly.
  static WordCraftBridge openLibraryForTesting(String path) =>
      WordCraftBridge._(openNativeCore(libraryPath: path));

  static WordCraftBridge? tryOpen() {
    try {
      return WordCraftBridge._(openNativeCore());
    } catch (_) {
      return null;
    }
  }

  Uint8List create(String firstParagraph) {
    final text = Uint8List.fromList(utf8.encode(firstParagraph));
    final p = _memory.allocate(text);
    try {
      return _memory.take(_create(p, text.length));
    } finally {
      _memory.release(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List docx) {
    final p = _memory.allocate(docx);
    try {
      final data = _memory.take(_inspect(p, docx.length));
      final result = jsonDecode(utf8.decode(data));
      if (result is! Map<String, dynamic>) {
        throw const FormatException('Некорректный ответ WordCraft');
      }
      return result;
    } finally {
      _memory.release(p);
    }
  }

  Uint8List appendParagraph(Uint8List docx, String value) {
    final data = _memory.allocate(docx);
    final text = Uint8List.fromList(utf8.encode(value));
    final t = _memory.allocate(text);
    try {
      return _memory.take(_append(data, docx.length, t, text.length));
    } finally {
      _memory.release(t);
      _memory.release(data);
    }
  }

  Uint8List edit(Uint8List docx, Map<String, dynamic> request) {
    final data = _memory.allocate(docx);
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final req = _memory.allocate(payload);
    try {
      return _memory.take(_edit(data, docx.length, req, payload.length));
    } finally {
      _memory.release(req);
      _memory.release(data);
    }
  }
}
