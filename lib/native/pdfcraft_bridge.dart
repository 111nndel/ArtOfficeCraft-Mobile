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

typedef _NativeSingle = _NativeResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef _DartSingle = _NativeResult Function(ffi.Pointer<ffi.Uint8>, int);
typedef _NativeEdit = _NativeResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef _DartEdit = _NativeResult Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _NativeFree = ffi.Void Function(_NativeResult);
typedef _DartFree = void Function(_NativeResult);
typedef _NativeVersion = ffi.Uint32 Function();
typedef _DartVersion = int Function();

/// PDFCraft COS/model page operations. File bytes stay on Android.
final class PdfCraftBridge {
  PdfCraftBridge._(ffi.DynamicLibrary library)
    : _create = library.lookupFunction<_NativeSingle, _DartSingle>(
        'ac_pdf_create',
      ),
      _inspect = library.lookupFunction<_NativeSingle, _DartSingle>(
        'ac_pdf_inspect',
      ),
      _edit = library.lookupFunction<_NativeEdit, _DartEdit>('ac_pdf_edit'),
      _free = library.lookupFunction<_NativeFree, _DartFree>('ac_result_free'),
      _version = library.lookupFunction<_NativeVersion, _DartVersion>(
        'ac_engine_abi_version',
      ) {
    if (_version() != 1) throw StateError('Несовместимый ABI Rust');
  }
  final _DartSingle _create;
  final _DartSingle _inspect;
  final _DartEdit _edit;
  final _DartFree _free;
  final _DartVersion _version;

  static PdfCraftBridge? tryOpen() {
    if (!Platform.isAndroid) return null;
    try {
      return PdfCraftBridge._(ffi.DynamicLibrary.open('libartoffice_core.so'));
    } catch (_) {
      return null;
    }
  }

  static PdfCraftBridge openLibraryForTesting(String path) =>
      PdfCraftBridge._(ffi.DynamicLibrary.open(path));

  ffi.Pointer<ffi.Uint8> _allocate(Uint8List bytes) {
    final p = calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) p.asTypedList(bytes.length).setAll(0, bytes);
    return p;
  }

  Uint8List _collect(_NativeResult result) {
    try {
      if (result.length < 0 ||
          result.length > 128 * 1024 * 1024 ||
          (result.ptr == ffi.nullptr && result.length > 0)) {
        throw StateError('PDFCraft вернул недопустимый буфер');
      }
      final bytes = result.length == 0
          ? Uint8List(0)
          : Uint8List.fromList(result.ptr.asTypedList(result.length));
      if (result.status != 0) {
        throw FormatException(utf8.decode(bytes, allowMalformed: true));
      }
      return bytes;
    } finally {
      _free(result);
    }
  }

  Uint8List create() {
    final p = _allocate(Uint8List(0));
    try {
      return _collect(_create(p, 0));
    } finally {
      calloc.free(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List bytes) {
    final p = _allocate(bytes);
    try {
      final value = jsonDecode(
        utf8.decode(_collect(_inspect(p, bytes.length))),
      );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Некорректные данные PDFCraft');
      }
      return value;
    } finally {
      calloc.free(p);
    }
  }

  Uint8List edit(Uint8List bytes, Map<String, dynamic> request) {
    final p = _allocate(bytes);
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final q = _allocate(payload);
    try {
      return _collect(_edit(p, bytes.length, q, payload.length));
    } finally {
      calloc.free(q);
      calloc.free(p);
    }
  }
}
