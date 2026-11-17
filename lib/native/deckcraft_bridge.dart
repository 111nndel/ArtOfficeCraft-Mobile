import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'native_core_library.dart';

/// DeckCraft PPTX import/export. All file bytes stay on the Android device.
final class DeckCraftBridge {
  DeckCraftBridge._(ffi.DynamicLibrary library)
    : _create = library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_pptx_create',
      ),
      _inspect = library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_pptx_inspect',
      ),
      _edit = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_pptx_edit',
      ),
      _image = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_pptx_image',
      ),
      _memory = NativeCoreMemory(library);
  final DartCoreOne _create;
  final DartCoreOne _inspect;
  final DartCoreTwo _edit;
  final DartCoreTwo _image;
  final NativeCoreMemory _memory;

  static DeckCraftBridge? tryOpen() {
    try {
      return DeckCraftBridge._(openNativeCore());
    } catch (_) {
      return null;
    }
  }

  static DeckCraftBridge openLibraryForTesting(String path) =>
      DeckCraftBridge._(openNativeCore(libraryPath: path));

  Uint8List create() {
    final p = _memory.allocate(Uint8List(0));
    try {
      return _memory.take(_create(p, 0));
    } finally {
      _memory.release(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List bytes) {
    final p = _memory.allocate(bytes);
    try {
      final value = jsonDecode(
        utf8.decode(_memory.take(_inspect(p, bytes.length))),
      );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Некорректные данные DeckCraft');
      }
      return value;
    } finally {
      _memory.release(p);
    }
  }

  /// Returns original embedded PNG/JPEG/WebP bytes (up to 8 MiB).
  /// The Rust side refuses unreferenced media IDs and external image links.
  Uint8List image(Uint8List bytes, int slide, int mediaId) {
    if (slide < 0 || mediaId < 0) {
      throw RangeError('Invalid picture reference');
    }
    final p = _memory.allocate(bytes);
    final payload = Uint8List.fromList(
      utf8.encode(jsonEncode(<String, int>{'slide': slide, 'media': mediaId})),
    );
    final q = _memory.allocate(payload);
    try {
      return _memory.take(_image(p, bytes.length, q, payload.length));
    } finally {
      _memory.release(q);
      _memory.release(p);
    }
  }

  Uint8List edit(Uint8List bytes, Map<String, dynamic> request) {
    final p = _memory.allocate(bytes);
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final q = _memory.allocate(payload);
    try {
      return _memory.take(_edit(p, bytes.length, q, payload.length));
    } finally {
      _memory.release(q);
      _memory.release(p);
    }
  }
}
