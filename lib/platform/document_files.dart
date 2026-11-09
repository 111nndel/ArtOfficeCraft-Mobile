import 'dart:typed_data';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../workspace/editor_kind.dart';

/// An opened file is an app-readable local copy. Null means cancellation;
/// failures throw and must leave the current document and dirty flag intact.
abstract interface class DocumentFiles {
  Future<String?> open(EditorKind kind);
  Future<String?> save({
    required EditorKind kind,
    required Uint8List bytes,
    required String name,
  });
}

/// The sole dependency on the existing Android/iOS file-dialog plugin.
final class MobileDocumentFiles implements DocumentFiles {
  const MobileDocumentFiles();

  @override
  Future<String?> open(EditorKind kind) => FlutterFileDialog.pickFile(
    params: OpenFileDialogParams(
      fileExtensionsFilter: [kind.extension],
      mimeTypesFilter: [kind.mimeType],
      allowedUtiTypes: [kind.utiType],
    ),
  );

  @override
  Future<String?> save({
    required EditorKind kind,
    required Uint8List bytes,
    required String name,
  }) => FlutterFileDialog.saveFile(
    params: SaveFileDialogParams(
      data: bytes,
      fileName: name,
      mimeTypesFilter: [kind.mimeType],
    ),
  );
}
