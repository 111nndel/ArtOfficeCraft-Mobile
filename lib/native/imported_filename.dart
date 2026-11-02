import 'dart:io';

/// Android SAF plugins often return an app-cache path without the original
/// extension. The actual document format is validated by its Rust parser,
/// not by the name of that temporary file.
String importedFilename(String path, String extension) {
  if (!RegExp(r'^[a-z0-9]+$').hasMatch(extension)) {
    throw ArgumentError.value(extension, 'extension', 'Invalid document type');
  }
  final raw = path.split(Platform.pathSeparator).last;
  if (raw.toLowerCase().endsWith('.$extension')) {
    return raw;
  }
  const fallback = <String, String>{
    'docx': 'Импортированный документ.docx',
    'xlsx': 'Импортированная книга.xlsx',
    'pptx': 'Импортированная презентация.pptx',
    'pdf': 'Импортированный документ.pdf',
  };
  return fallback[extension] ?? 'Импортированный.$extension';
}
