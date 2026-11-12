import 'dart:io';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/platform/application_storage.dart';
import 'package:artofficecraft_mobile/platform/bundled_pdf_image_ocr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Models extends CachingAssetBundle {
  final calls = <String>[];
  bool broken = false;
  @override
  Future<ByteData> load(String key) async {
    calls.add(key);
    return ByteData(
      broken
          ? 1
          : key.endsWith('eng.traineddata')
          ? 4113088
          : 3861738,
    );
  }
}

void main() {
  test(
    'concurrent model preparation copies once and repairs incomplete cache',
    () async {
      final root = await Directory.systemTemp.createTemp('aoc-ocr-models-');
      addTearDown(() => root.delete(recursive: true));
      final storage = DirectoryApplicationStorage(root);
      final assets = Models();
      final paths = await Future.wait([
        preparePdfOcrModels(storage, assets: assets),
        preparePdfOcrModels(storage, assets: assets),
      ]);
      expect(paths[0], paths[1]);
      expect(assets.calls.length, 2);
      await File('${paths[0]}/rus.traineddata').writeAsBytes([0]);
      await preparePdfOcrModels(storage, assets: assets);
      expect(assets.calls.length, 3);
      expect(await File('${paths[0]}/rus.traineddata').length(), 3861738);
      expect(
        Directory(paths[0])
            .listSync()
            .where((f) => f.path.endsWith('.pending')),
        isEmpty,
      );
    },
  );
  test(
    'bad bundled model fails without poisoning a later preparation',
    () async {
      final root = await Directory.systemTemp.createTemp('aoc-ocr-models-');
      addTearDown(() => root.delete(recursive: true));
      final storage = DirectoryApplicationStorage(root);
      final assets = Models()..broken = true;
      await expectLater(
        preparePdfOcrModels(storage, assets: assets),
        throwsFormatException,
      );
      assets.broken = false;
      final path = await preparePdfOcrModels(storage, assets: assets);
      expect(await File('$path/eng.traineddata').length(), 4113088);
    },
  );
}
