import 'package:artofficecraft_mobile/native/pdf_page_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'shared OCR result preserves Russian/English and normalized word boxes',
    () {
      final result = parsePdfOcrResult({
        'text': ' Русский English ',
        'words': [
          {
            'text': 'Русский',
            'rect': [0.1, 0.2, 0.4, 0.3],
          },
          {
            'text': 'English',
            'rect': [0.5, 0.2, 0.9, 0.3],
          },
        ],
      });
      expect(result.text, 'Русский English');
      expect(result.words.first.text, 'Русский');
      expect(result.words.first.rect, [0.1, 0.2, 0.4, 0.3]);
      expect(result.words.last.text, 'English');
    },
  );

  test('rejects malformed, reversed and oversized OCR responses', () async {
    for (final response in [
      null,
      {'text': List.filled(64 * 1024 + 1, 'x').join(), 'words': []},
      {
        'text': 'x',
        'words': List.filled(4097, {
          'text': 'x',
          'rect': [0, 0, 1, 1],
        }),
      },
      for (final rect in [
        [0.8, 0, 0.2, 1],
        [0, 0.5, 1, 0.5],
        [0, 0, double.nan, 1],
        [0, 0, 1, 2],
      ])
        {
          'text': 'x',
          'words': [
            {'text': 'x', 'rect': rect},
          ],
        },
      {
        'text': 'x',
        'words': [
          {
            'text': List.filled(64 * 1024 + 1, 'x').join(),
            'rect': [0, 0, 1, 1],
          },
        ],
      },
    ]) {
      expect(() => parsePdfOcrResult(response), throwsFormatException);
    }
  });
}
