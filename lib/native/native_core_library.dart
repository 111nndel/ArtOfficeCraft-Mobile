import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The single AcResult layout exported by every operation in ABI 1.
final class NativeCoreResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  external ffi.Pointer<ffi.Uint8> ptr;
  @ffi.IntPtr()
  external int length;
  @ffi.IntPtr()
  external int capacity;
}

typedef NativeCoreOne = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef DartCoreOne = NativeCoreResult Function(ffi.Pointer<ffi.Uint8>, int);
typedef NativeCoreTwo = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef DartCoreTwo = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef NativeCoreThree = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef DartCoreThree = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _NativeFree = ffi.Void Function(NativeCoreResult);
typedef _DartFree = void Function(NativeCoreResult);

/// Dart owns input allocations; Rust owns results until they are copied and freed.
/// Decoders only receive Dart bytes, including on native errors and empty output.
final class NativeCoreMemory {
  NativeCoreMemory(ffi.DynamicLibrary library)
    : _free = library.lookupFunction<_NativeFree, _DartFree>('ac_result_free');
  final _DartFree _free;

  ffi.Pointer<ffi.Uint8> allocate(Uint8List bytes) {
    final pointer = calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  void release(ffi.Pointer<ffi.Uint8> pointer) => calloc.free(pointer);

  Uint8List take(NativeCoreResult result, {int maxBytes = 128 * 1024 * 1024}) {
    try {
      if (result.length < 0 ||
          result.length > maxBytes ||
          result.ptr == ffi.nullptr && result.length > 0) {
        throw StateError('Недопустимый ответ Rust');
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
}

typedef _NativeAbi = ffi.Uint32 Function();
typedef _DartAbi = int Function();

/// Bundle locations only: document folders and the working directory are never
/// searched for executable code. The desktop packagers must supply this file.
String? nativeCoreLibraryPath(String operatingSystem, String executable) {
  final windows = operatingSystem == 'windows';
  final location = Uri.file(executable, windows: windows);
  final relative = switch (operatingSystem) {
    'android' => null,
    'linux' => 'lib/libartoffice_core.so',
    'windows' => 'artoffice_core.dll',
    'macos' => '../Frameworks/libartoffice_core.dylib',
    _ => null,
  };
  if (operatingSystem == 'android') return 'libartoffice_core.so';
  return relative == null
      ? null
      : location.resolve(relative).toFilePath(windows: windows);
}

/// All four document bridges and build information use the same ABI check.
/// iOS must statically link and export the core symbols into the app process.
ffi.DynamicLibrary openNativeCore({String? libraryPath}) {
  final ffi.DynamicLibrary library;
  if (libraryPath != null) {
    library = ffi.DynamicLibrary.open(libraryPath);
  } else if (Platform.isIOS) {
    library = ffi.DynamicLibrary.process();
  } else {
    final path = nativeCoreLibraryPath(
      Platform.operatingSystem,
      Platform.resolvedExecutable,
    );
    if (path == null) {
      throw UnsupportedError('Native document core unavailable');
    }
    library = ffi.DynamicLibrary.open(path);
  }
  final abi = library.lookupFunction<_NativeAbi, _DartAbi>(
    'ac_engine_abi_version',
  );
  if (abi() != 1) throw StateError('Несовместимая версия интерфейса Rust');
  return library;
}
