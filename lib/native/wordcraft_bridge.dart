import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _NativeResult extends ffi.Struct {
  @ffi.Int32()
  external int status;

  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.IntPtr()
  external int length;

  @ffi.IntPtr()
  external int capacity;
}

typedef _RustOne = _NativeResult Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DartOne = _NativeResult Function(ffi.Pointer<ffi.Uint8>, int);

typedef _RustTwo = _NativeResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef _DartTwo = _NativeResult Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _RustFree = ffi.Void Function(_NativeResult);
typedef _DartFree = void Function(_NativeResult);
typedef _RustVersion = ffi.Uint32 Function();
typedef _DartVersion = int Function();

/// WordCraft native Android adapter. No document data is sent over the network.
///
/// All Rust allocated buffers are freed even when decoding throws.
/// This API is synchronous: keep files reasonably small until a worker isolate
/// is wired in. Error messages are surfaced rather than pretending to save.
final class WordCraftBridge {
  WordCraftBridge._(ffi.DynamicLibrary library)
    : _inspect = library.lookupFunction<_RustOne, _DartOne>('ac_docx_inspect'),
      _create = library.lookupFunction<_RustOne, _DartOne>('ac_docx_create'),
      _append = library.lookupFunction<_RustTwo, _DartTwo>(
        'ac_docx_append_paragraph',
      ),
      _free = library.lookupFunction<_RustFree, _DartFree>('ac_result_free'),
      _abi = library.lookupFunction<_RustVersion, _DartVersion>(
        'ac_engine_abi_version',
      ) {
    if (_abi() != 1) {
      throw StateError('Несовместимая версия интерфейса Rust');
    }
  }

  final _DartOne _inspect;
  final _DartOne _create;
  final _DartTwo _append;
  final _DartFree _free;
  final _DartVersion _abi;

  /// Desktop smoke tests may inject the native Windows library explicitly.
  static WordCraftBridge openLibraryForTesting(String path) =>
      WordCraftBridge._(ffi.DynamicLibrary.open(path));

  static WordCraftBridge? tryOpen() {
    if (!Platform.isAndroid) return null;
    try {
      return WordCraftBridge._(ffi.DynamicLibrary.open('libartoffice_core.so'));
    } catch (_) {
      return null;
    }
  }

  ffi.Pointer<ffi.Uint8> _write(Uint8List bytes) {
    final pointer = calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
    }
    return pointer;
  }

  Uint8List _receive(_NativeResult result) {
    try {
      if (result.length < 0 || result.length > 128 * 1024 * 1024) {
        throw StateError('Недопустимый размер ответа Rust');
      }
      if (result.ptr == ffi.nullptr && result.length > 0) {
        throw StateError('Rust вернул пустой указатель');
      }
      final bytes = Uint8List.fromList(result.ptr.asTypedList(result.length));
      if (result.status != 0) {
        throw FormatException(utf8.decode(bytes, allowMalformed: true));
      }
      return bytes;
    } finally {
      _free(result);
    }
  }

  Uint8List create(String firstParagraph) {
    final text = Uint8List.fromList(utf8.encode(firstParagraph));
    final p = _write(text);
    try {
      return _receive(_create(p, text.length));
    } finally {
      calloc.free(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List docx) {
    final p = _write(docx);
    try {
      final data = _receive(_inspect(p, docx.length));
      final result = jsonDecode(utf8.decode(data));
      if (result is! Map<String, dynamic>) {
        throw const FormatException('Некорректный ответ WordCraft');
      }
      return result;
    } finally {
      calloc.free(p);
    }
  }

  Uint8List appendParagraph(Uint8List docx, String value) {
    final data = _write(docx);
    final text = Uint8List.fromList(utf8.encode(value));
    final t = _write(text);
    try {
      return _receive(_append(data, docx.length, t, text.length));
    } finally {
      calloc.free(t);
      calloc.free(data);
    }
  }
}
