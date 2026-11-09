import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/native_core_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Native libraries resolve beside the application, independent of cwd', () {
    expect(
      nativeCoreLibraryPath('linux', '/opt/Art Office/bin/editor'),
      '/opt/Art Office/bin/lib/libartoffice_core.so',
    );
    expect(
      nativeCoreLibraryPath('windows', r'C:\Art Office\editor.exe'),
      r'C:\Art Office\artoffice_core.dll',
    );
    expect(
      nativeCoreLibraryPath('macos', '/Applications/Office.app/Contents/MacOS/app'),
      '/Applications/Office.app/Contents/Frameworks/libartoffice_core.dylib',
    );
    expect(nativeCoreLibraryPath('android', '/system/bin/app_process64'),
      'libartoffice_core.so');
    expect(nativeCoreLibraryPath('unknown', '/tmp/app'), isNull);
  });

  test('Missing native library disables every backend without a worker', () {
    for (final kind in NativeDocumentKind.values) {
      expect(
        NativeDocumentBackend.tryOpen(kind, libraryPath: '/missing/core/library'),
        isNull,
      );
    }
  });
}
