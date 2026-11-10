import 'package:artofficecraft_mobile/native/word_document_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Navigation uses paragraph positions despite non-paragraph block gaps',
    () {
      final source = <Map<String, dynamic>>[
        {'block': 0, 'text': 'Начало', 'outlineLevel': 0},
        {'block': 2, 'text': 'Body', 'outlineLevel': 9},
        {'block': 5, 'text': 'Подраздел 😀', 'outlineLevel': 2},
        {'block': 7, 'text': '  ', 'outlineLevel': 1},
        {'block': 9, 'text': 'Bad metadata', 'outlineLevel': -1},
      ];
      final index = WordDocumentIndex(source);
      source[0]['text'] = 'Mutated';
      expect(index.blocks.first['text'], 'Начало');
      expect(index.positionOf(5), 2);
      expect(index.positionOf(1), isNull);
      expect(index.headings, [
        (position: 0, level: 0, text: 'Начало'),
        (position: 2, level: 2, text: 'Подраздел 😀'),
      ]);
    },
  );

  test(
    'Exact UTF16 search refreshes for query, draft, cancel and new snapshot',
    () {
      final index = WordDocumentIndex([
        {'block': 0, 'text': '😀 cat cat Cat', 'editable': true},
        {'block': 4, 'text': 'cat', 'editable': false},
      ]);
      expect(index.find('cat'), [
        (block: 0, start: 3, end: 6, editable: true),
        (block: 0, start: 7, end: 10, editable: true),
        (block: 4, start: 0, end: 3, editable: false),
      ]);
      expect(index.find('cat', draftBlock: 0, draft: '😀 cat'), [
        (block: 0, start: 3, end: 6, editable: true),
        (block: 4, start: 0, end: 3, editable: false),
      ]);
      expect(index.find('cat', draftBlock: 0, draft: 'gone'), [
        (block: 4, start: 0, end: 3, editable: false),
      ]);
      expect(index.find('cat').length, 3);
      expect(index.find('Cat').single.start, 11);
      expect(index.find(''), isEmpty);
      expect(
        WordDocumentIndex([
          {'block': 0, 'text': 'changed'},
        ]).find('cat'),
        isEmpty,
      );
    },
  );

  test('Search stops at the existing 10000 non-overlapping match bound', () {
    final index = WordDocumentIndex([
      {'block': 0, 'text': 'a' * 30000},
    ]);
    final hits = index.find('aa');
    expect(hits.length, 10000);
    expect(hits.last.start, 19998);
    expect(() => hits.clear(), throwsUnsupportedError);
  });
}
