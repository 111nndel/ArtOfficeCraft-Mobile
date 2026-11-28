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
      _imageReader = library.providesSymbol('ac_pptx_image_reader')
          ? library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
              'ac_pptx_image_reader',
            )
          : null,
      _memory = NativeCoreMemory(library);
  final DartCoreOne _create;
  final DartCoreOne _inspect;
  final DartCoreTwo _edit;
  final DartCoreTwo _image;
  final DartCoreTwo? _imageReader;
  final NativeCoreMemory _memory;

  static final _empty = Uint8List(0);

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
    final p = _memory.allocate(_empty);
    try {
      return _memory.take(_create(p, 0));
    } finally {
      _memory.release(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List bytes) {
    final p = _memory.allocate(bytes);
    try {
      return _object(_memory.take(_inspect(p, bytes.length)));
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
    return _request(_image, bytes, {'slide': slide, 'media': mediaId});
  }

  bool get supportsImageReader => _imageReader != null;

  ({int? session, Map<String, dynamic>? preview}) openImageReader(
    Uint8List bytes, {
    required bool preview,
  }) {
    final response = _object(
      _request(_imageReader!, bytes, {'reader': 'open', 'preview': preview}),
    );
    return (
      session: response['session'] as int?,
      preview: response['preview'] as Map<String, dynamic>?,
    );
  }

  Uint8List? readImage(int session, int slide, int mediaId) {
    final result = _request(_imageReader!, _empty, {
      'reader': 'read',
      'session': session,
      'slide': slide,
      'media': mediaId,
    });
    return result.isEmpty ? null : result;
  }

  void closeImageReader(int session) {
    _request(_imageReader!, _empty, {'reader': 'close', 'session': session});
  }

  Uint8List edit(Uint8List bytes, Map<String, dynamic> request) =>
      _request(_edit, bytes, request);

  Map<String, dynamic> _object(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Некорректные данные DeckCraft');
    }
    return value;
  }

  Uint8List _request(
    DartCoreTwo operation,
    Uint8List bytes,
    Map<String, dynamic> request,
  ) {
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final p = _memory.allocate(bytes);
    try {
      final q = _memory.allocate(payload);
      try {
        return _memory.take(operation(p, bytes.length, q, payload.length));
      } finally {
        _memory.release(q);
      }
    } finally {
      _memory.release(p);
    }
  }
}
