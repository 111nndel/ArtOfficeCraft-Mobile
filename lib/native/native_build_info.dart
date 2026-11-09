import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'native_core_library.dart';

final class _InfoResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  external ffi.Pointer<ffi.Uint8> ptr;
  @ffi.IntPtr()
  external int length;
  @ffi.IntPtr()
  external int capacity;
}

typedef _NativeInfo = _InfoResult Function();
typedef _DartInfo = _InfoResult Function();
typedef _NativeFree = ffi.Void Function(_InfoResult);
typedef _DartFree = void Function(_InfoResult);

Future<Map<String, dynamic>?> readNativeBuildInfo({
  String? libraryPath,
}) => Isolate.run(() {
  final ffi.DynamicLibrary library;
  try {
    library = openNativeCore(libraryPath: libraryPath);
  } catch (_) {
    if (libraryPath != null) rethrow;
    return null;
  }
  final info = library.lookupFunction<_NativeInfo, _DartInfo>('ac_engine_info');
  final free = library.lookupFunction<_NativeFree, _DartFree>('ac_result_free');
  final result = info();
  try {
    if (result.status != 0 ||
        result.length < 2 ||
        result.length > 1024 * 1024 ||
        result.ptr == ffi.nullptr) {
      throw StateError('Некорректные сведения о нативной сборке');
    }
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(result.ptr.asTypedList(result.length))) as Map,
    );
  } finally {
    free(result);
  }
});
