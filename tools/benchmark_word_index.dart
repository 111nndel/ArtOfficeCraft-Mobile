import 'dart:convert';
import 'dart:io';

import '../lib/native/word_document_index.dart';

// Synthetic unchanged-query reads, compiled to AOT by CI. Not phone frame time.
void main(List<String> args) {
  final blocks = List.generate(
    20000,
    (i) => <String, dynamic>{
      'block': i * 2,
      'editable': true,
      'text': 'Paragraph $i ${'abcdef ' * 20}${i == 19999 ? 'needle 😀' : ''}',
      if (i % 1000 == 0) 'outlineLevel': 0,
    },
  );
  List<WordFindMatch> baseline() {
    final found = <WordFindMatch>[];
    for (final b in blocks) {
      final text = b['text'] as String;
      var at = 0;
      while ((at = text.indexOf('needle', at)) >= 0) {
        found.add((
          block: b['block'] as int,
          start: at,
          end: at + 6,
          editable: true,
        ));
        at += 6;
        if (found.length >= 10000) return found;
      }
    }
    return found;
  }

  final clock = Stopwatch()..start();
  final index = WordDocumentIndex(blocks);
  final buildUs = clock.elapsedMicroseconds;
  clock.reset();
  final expected = index.find('needle');
  final coldUs = clock.elapsedMicroseconds;
  if (expected.length != 1 || expected.single.block != 39998)
    throw StateError('Wrong result');
  final times = {'baseline': <int>[], 'cached': <int>[]};
  for (var i = 0; i < 30; i++) {
    for (final mode
        in i.isEven ? ['baseline', 'cached'] : ['cached', 'baseline']) {
      clock.reset();
      final result = mode == 'baseline' ? baseline() : index.find('needle');
      times[mode]!.add(clock.elapsedMicroseconds);
      if (jsonEncode(
            result.map((m) => [m.block, m.start, m.end, m.editable]).toList(),
          ) !=
          jsonEncode(
            expected.map((m) => [m.block, m.start, m.end, m.editable]).toList(),
          )) {
        throw StateError('Search result changed');
      }
    }
  }
  double median(List<int> samples) {
    final sorted = [...samples]..sort();
    return (sorted[14] + sorted[15]) / 2;
  }

  final report = {
    'scope': 'Dart AOT Linux; 20000 synthetic paragraphs; 30 unchanged-query reads, not Android FPS',
    'paragraphs': blocks.length,
    'equalOutputs': true,
    'indexBuildUs': buildUs,
    'coldFindUs': coldUs,
    'medianUs': {for (final e in times.entries) e.key: median(e.value)},
    'samplesUs': times,
  };
  File(args.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
}
