import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'editor_kind.dart';

/// The same restriction is used from Home and each editor's File menu.
OpenFileDialogParams documentPickerParams(EditorKind kind) =>
    OpenFileDialogParams(
      fileExtensionsFilter: [kind.extension],
      mimeTypesFilter: [kind.mimeType],
      allowedUtiTypes: [kind.utiType],
    );

Future<String?> pickDocument(EditorKind kind) =>
    FlutterFileDialog.pickFile(params: documentPickerParams(kind));
