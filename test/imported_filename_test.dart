import 'dart:io';

import 'package:artofficecraft_mobile/native/imported_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Temporary Android SAF path without extension gets safe PDF label', () {
    final cachePath = [
      'data',
      'user',
      '0',
      'ai.artofficecraft.artofficecraft_mobile',
      'cache',
      'flutter_file_dialog',
      'document_copy_01832',
    ].join(Platform.pathSeparator);
    expect(importedFilename(cachePath, 'pdf'), 'Импортированный документ.pdf');
    expect(
      importedFilename(cachePath, 'pptx'),
      'Импортированная презентация.pptx',
    );
    expect(importedFilename(cachePath, 'xlsx'), 'Импортированная книга.xlsx');
    expect(
      importedFilename(cachePath, 'docx'),
      'Импортированный документ.docx',
    );
  });
  test('Real document names are preserved regardless of extension case', () {
    expect(importedFilename('budget.XLSX', 'xlsx'), 'budget.XLSX');
    expect(importedFilename('annual.report.PDF', 'pdf'), 'annual.report.PDF');
  });
  test('Reject unsupported requested suffix', () {
    expect(() => importedFilename('anything', '../pdf'), throwsArgumentError);
  });
}
