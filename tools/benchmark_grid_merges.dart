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
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  final medians = {for (final e in samples.entries) e.key: median(e.value)};
  final points = List.generate(
    30000,
    (_) => (random.nextInt(500100), random.nextInt(60)),
  );
  GridMerge? previousPoint(int row, int column) =>
      merges.first.contains(row, column)
      ? merges.first
      : layout.mergesIn(GridBounds(row, column, row, column)).firstOrNull;
  for (final point in points) {
    if (!identical(
      previousPoint(point.$1, point.$2),
      layout.mergeAt(point.$1, point.$2),
    )) {
      throw StateError('Point merge changed');
    }
  }
  final pointSamples = {'previous': <int>[], 'current': <int>[]};
  int? pointChecksum;
  for (var i = 0; i < 7; i++) {
    for (final mode
        in i.isEven ? ['previous', 'current'] : ['current', 'previous']) {
      clock.reset();
      var checksum = 0;
      for (final point in points) {
        final hit = mode == 'previous'
            ? previousPoint(point.$1, point.$2)
            : layout.mergeAt(point.$1, point.$2);
        if (hit != null) checksum += hit.row + hit.column;
      }
      pointSamples[mode]!.add(clock.elapsedMicroseconds);
      pointChecksum ??= checksum;
      if (pointChecksum != checksum) throw StateError('Point output changed');
    }
  }
  final report = {
    'scope': 'Dart AOT Linux; 10001 synthetic merges, including one spanning all rows; 256 window queries per sample; not Android FPS',
    'merges': merges.length,
    'queriesPerSample': queries.length,
    'equalOutputs': true,
    'indexBuildUs': buildUs,
    'medianBatchUs': medians,
    'medianSpeedup': medians['linear']! / medians['indexed']!,
    'samplesUs': samples,
    'pointLookup': {
      'queriesPerSample': points.length,
      'equalOutputs': true,
      'previousMedianUs': median(pointSamples['previous']!),
      'currentMedianUs': median(pointSamples['current']!),
      'medianSpeedup':
          median(pointSamples['previous']!) / median(pointSamples['current']!),
      'samplesUs': pointSamples,
    },
  };
  File(args.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
}
