import '../platform/document_files.dart';
import 'editor_kind.dart';

Future<String?> pickDocument(
  EditorKind kind, {
  DocumentFiles files = const MobileDocumentFiles(),
}) => files.open(kind);
