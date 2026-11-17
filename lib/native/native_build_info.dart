import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'native_core_library.dart';

typedef _NativeInfo = NativeCoreResult Function();
typedef _DartInfo = NativeCoreResult Function();

Future<Map<String, dynamic>?> readNativeBuildInfo({String? libraryPath}) =>
    Isolate.run(() {
      final ffi.DynamicLibrary library;
      try {
        library = openNativeCore(libraryPath: libraryPath);
      } catch (_) {
        if (libraryPath != null) rethrow;
        return null;
      }
      final info = library.lookupFunction<_NativeInfo, _DartInfo>(
        'ac_engine_info',
      );
      final bytes = NativeCoreMemory(library)
          .take(info(), maxBytes: 1024 * 1024);
      if (bytes.length < 2) {
        throw StateError('Некорректные сведения о нативной сборке');
      }
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    });
