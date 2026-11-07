import 'package:flutter/material.dart';

enum EditorKind { word, excel, slides, pdf }

extension EditorInfo on EditorKind {
  String get title => '${label == 'Таблица' ? 'Книга' : label}.$extension';
  String get label => switch (this) {
    EditorKind.word => 'Документ',
    EditorKind.excel => 'Таблица',
    EditorKind.slides => 'Презентация',
    EditorKind.pdf => 'PDF',
  };
  String get extension => switch (this) {
    EditorKind.word => 'docx',
    EditorKind.excel => 'xlsx',
    EditorKind.slides => 'pptx',
    EditorKind.pdf => 'pdf',
  };
  String get format => extension.toUpperCase();
  String get mimeType => switch (this) {
    EditorKind.word =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    EditorKind.excel =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    EditorKind.slides => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    EditorKind.pdf => 'application/pdf',
  };
  String get utiType => switch (this) {
    EditorKind.word => 'org.openxmlformats.wordprocessingml.document',
    EditorKind.excel => 'org.openxmlformats.spreadsheetml.sheet',
    EditorKind.slides => 'org.openxmlformats.presentationml.presentation',
    EditorKind.pdf => 'com.adobe.pdf',
  };
  String get description => switch (this) {
    EditorKind.word => 'Текст и документы',
    EditorKind.excel => 'Данные и формулы',
    EditorKind.slides => 'Слайды и истории',
    EditorKind.pdf => 'Чтение и страницы',
  };
  IconData get glyph => switch (this) {
    EditorKind.word => Icons.description_outlined,
    EditorKind.excel => Icons.grid_on_outlined,
    EditorKind.slides => Icons.slideshow_outlined,
    EditorKind.pdf => Icons.picture_as_pdf_outlined,
  };
  Color get tint => switch (this) {
    EditorKind.word => const Color(0xff3565ca),
    EditorKind.excel => const Color(0xff17815c),
    EditorKind.slides => const Color(0xffcc6243),
    EditorKind.pdf => const Color(0xffc94e59),
  };
}
