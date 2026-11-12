import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:artofficecraft_mobile/native/grid_layout.dart';

// Compare the previous linear scan with the exact same merge snapshot/queries.
// Timings are evidence, never a threshold or a claim about phone frame time.
void main(List<String> args) {
  final random = Random(50);
  final merges = [
    const GridMerge(0, 40, 1048575, 40),
    for (var i = 0; i < 10000; i++)
      GridMerge(i * 50, (i % 8) * 4, i * 50 + 1, (i % 8) * 4 + 2),
  ]..shuffle(random);
  final queries = [
    for (var i = 0; i < 256; i++) GridBounds(i * 1937, 0, i * 1937 + 63, 48),
  ];
  List<GridMerge> linear(GridBounds q) => [
    for (final m in merges)
      if (m.row <= q.endRow &&
          m.endRow >= q.row &&
          m.column <= q.endColumn &&
          m.endColumn >= q.column)
        m,
  ];
  final clock = Stopwatch()..start();
  final layout = GridLayout(GridAxis(1048576, 20), GridAxis(16384, 64), merges);
  layout.mergesIn(queries.first);
  final buildUs = clock.elapsedMicroseconds;
  for (final q in queries) {
    final expected = linear(q), actual = layout.mergesIn(q);
    if (expected.length != actual.length ||
        expected.indexed.any((e) => !identical(e.$2, actual[e.$1]))) {
      throw StateError('Merge query changed');
    }
    final point = merges.where((m) => m.contains(q.row, q.column)).firstOrNull;
    if (!identical(layout.mergeAt(q.row, q.column), point)) {
      throw StateError('First merge changed');
    }
  }
  final samples = {'linear': <int>[], 'indexed': <int>[]};
  int? expectedChecksum;
  for (var i = 0; i < 30; i++) {
    for (final mode
        in i.isEven ? ['linear', 'indexed'] : ['indexed', 'linear']) {
      clock.reset();
      var checksum = 0;
      for (final q in queries) {
        for (final m in mode == 'linear' ? linear(q) : layout.mergesIn(q)) {
          checksum = (checksum * 31 + m.row + m.column) & 0x7fffffff;
        }
      }
      samples[mode]!.add(clock.elapsedMicroseconds);
      expectedChecksum ??= checksum;
      if (expectedChecksum != checksum) throw StateError('Output changed');
    }
  }
  double median(List<int> values) {
    final sorted = [...values]..sort();
    return (sorted[14] + sorted[15]) / 2;
  }

  final medians = {for (final e in samples.entries) e.key: median(e.value)};
  final report = {
    'scope': 'Dart AOT Linux; 10001 synthetic merges, including one spanning all rows; 256 window queries per sample; not Android FPS',
    'merges': merges.length,
    'queriesPerSample': queries.length,
    'equalOutputs': true,
    'indexBuildUs': buildUs,
    'medianBatchUs': medians,
    'medianSpeedup': medians['linear']! / medians['indexed']!,
    'samplesUs': samples,
  };
  File(args.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
}
