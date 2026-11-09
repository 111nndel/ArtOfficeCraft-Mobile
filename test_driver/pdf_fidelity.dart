import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final root = Directory('build/pdf-renderer-fidelity/results');
  final manifest = jsonDecode(await File('${root.path}/fixture/manifest.json').readAsString()) as Map;
  await integrationDriver(responseDataCallback: (data) async {
    final rasters = data?['rasters'];
    if (rasters is! List || rasters.length != 16 || data?['fixtureSha256'] != manifest['pdfSha256']) {
      throw const FormatException('Missing Android raster evidence');
    }
    final seen = <String>{};
    var total = 0;
    for (final entry in rasters) {
      if (entry case {'renderer': String renderer, 'page': int page, 'width': int width, 'height': int height, 'png': String encoded}
          when (renderer == 'android' || renderer == 'rust-android') && page >= 1 && page <= 8 && encoded.length <= 12 * 1024 * 1024) {
        if (!seen.add('$renderer/$page')) throw const FormatException('Duplicate raster page');
        final png = base64Decode(encoded);
        total += png.length;
        if (png.length < 24 || png.length > 8 * 1024 * 1024 || total > 48 * 1024 * 1024 ||
            png.take(8).join(',') != '137,80,78,71,13,10,26,10') {
          throw const FormatException('Invalid or oversized PNG evidence');
        }
        final header = ByteData.sublistView(png);
        if (header.getUint32(16) != width || header.getUint32(20) != height) {
          throw const FormatException('Raster dimensions do not match metadata');
        }
        final output = await Directory('${root.path}/$renderer').create(recursive: true);
        await File('${output.path}/page-${page.toString().padLeft(2, '0')}.png').writeAsBytes(png, flush: true);
      } else {
        throw const FormatException('Invalid raster response');
      }
    }
  });
}
