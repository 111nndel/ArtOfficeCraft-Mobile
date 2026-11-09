import 'dart:ffi' as ffi;
import 'dart:io';

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
    if (path == null) throw UnsupportedError('Native document core unavailable');
    library = ffi.DynamicLibrary.open(path);
  }
  final abi = library.lookupFunction<_NativeAbi, _DartAbi>(
    'ac_engine_abi_version',
  );
  if (abi() != 1) throw StateError('Несовместимая версия интерфейса Rust');
  return library;
}
