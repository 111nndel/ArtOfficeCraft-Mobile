import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _GridResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  external ffi.Pointer<ffi.Uint8> ptr;
  @ffi.IntPtr()
  external int length;
  @ffi.IntPtr()
  external int capacity;
}

typedef _NativeOne = _GridResult Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef _DartOne = _GridResult Function(ffi.Pointer<ffi.Uint8>, int);
typedef _NativeTwo = _GridResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef _DartTwo = _GridResult Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _NativeFree = ffi.Void Function(_GridResult);
typedef _DartFree = void Function(_GridResult);
typedef _NativeAbi = ffi.Uint32 Function();
typedef _DartAbi = int Function();

/// GridCraft native engine. Synchronous FFI used by the background DocumentBackend isolate.
/// No data leaves the phone; saving occurs only into a user-chosen new file.
final class GridCraftBridge {
  GridCraftBridge._(ffi.DynamicLibrary library)
    : _create = library.lookupFunction<_NativeOne, _DartOne>('ac_xlsx_create'),
      _inspect = library.lookupFunction<_NativeOne, _DartOne>(
        'ac_xlsx_inspect',
      ),
      _edit = library.lookupFunction<_NativeTwo, _DartTwo>('ac_xlsx_set_cell'),
      _free = library.lookupFunction<_NativeFree, _DartFree>('ac_result_free'),
      _abi = library.lookupFunction<_NativeAbi, _DartAbi>(
        'ac_engine_abi_version',
      ) {
    if (_abi() != 1) throw StateError('Несовместимая версия Rust ABI');
  }
  final _DartOne _create;
  final _DartOne _inspect;
  final _DartTwo _edit;
  final _DartFree _free;
  final _DartAbi _abi;

  static GridCraftBridge? tryOpen() {
    if (!Platform.isAndroid) return null;
    try {
      return GridCraftBridge._(ffi.DynamicLibrary.open('libartoffice_core.so'));
    } catch (_) {
      return null;
    }
  }

  static GridCraftBridge openLibraryForTesting(String path) =>
      GridCraftBridge._(ffi.DynamicLibrary.open(path));

  ffi.Pointer<ffi.Uint8> _alloc(Uint8List bytes) {
    final p = calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) p.asTypedList(bytes.length).setAll(0, bytes);
    return p;
  }

  Uint8List _read(_GridResult value) {
    try {
      if (value.length < 0 ||
          value.length > 128 * 1024 * 1024 ||
          value.ptr == ffi.nullptr && value.length > 0) {
        throw StateError('Недопустимый ответ GridCraft');
      }
      final bytes = value.length == 0
          ? Uint8List(0)
          : Uint8List.fromList(value.ptr.asTypedList(value.length));
      if (value.status != 0) {
        throw FormatException(utf8.decode(bytes, allowMalformed: true));
      }
      return bytes;
    } finally {
      _free(value);
    }
  }

  Uint8List create() {
    final p = _alloc(Uint8List(0));
    try {
      return _read(_create(p, 0));
    } finally {
      calloc.free(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List workbook) {
    final p = _alloc(workbook);
    try {
      final out = jsonDecode(utf8.decode(_read(_inspect(p, workbook.length))));
      if (out is! Map<String, dynamic>) {
        throw const FormatException('Некорректный ответ');
      }
      return out;
    } finally {
      calloc.free(p);
    }
  }

  Uint8List editCell(
    Uint8List workbook,
    int sheet,
    String address,
    String value,
  ) {
    return edit(workbook, {'sheet': sheet, 'address': address, 'value': value});
  }

  Uint8List edit(Uint8List workbook, Map<String, dynamic> changes) {
    final p = _alloc(workbook);
    final request = Uint8List.fromList(utf8.encode(jsonEncode(changes)));
    final q = _alloc(request);
    try {
      return _read(_edit(p, workbook.length, q, request.length));
    } finally {
      calloc.free(q);
      calloc.free(p);
    }
  }
}
