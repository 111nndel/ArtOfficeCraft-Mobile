import 'dart:io';

import 'package:flutter/services.dart';

import '../native/native_pdf_image_ocr.dart';
import 'application_storage.dart';

Future<void> _modelWrites = Future.value();

/// Models ship in Flutter assets. Only this app-owned directory is writable;
/// recognition receives a tessdata path, never Android Context or Bitmap.
Future<String> preparePdfOcrModels(
  ApplicationStorage storage, {
  AssetBundle? assets,
}) {
  final result = _modelWrites.then((_) async {
    final root = await storage.workspaceDirectory();
    final directory = await Directory('${root.path}/ocr-65727574/tessdata')
        .create(recursive: true);
    for (final (name, size) in [('eng', 4113088), ('rus', 3861738)]) {
      final target = File('${directory.path}/$name.traineddata');
      if (await target.exists() && await target.length() == size) continue;
      final data = await (assets ?? rootBundle).load(
        'assets/ocr/tessdata/$name.traineddata',
      );
      if (data.lengthInBytes != size) {
        throw const FormatException('Invalid bundled OCR model');
      }
      final temporary = File('${target.path}.pending');
      try {
        await temporary.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        await temporary.rename(target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return directory.path;
  });
  _modelWrites = result.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return result;
}

NativePdfImageOcr bundledPdfImageOcr(ApplicationStorage storage) =>
    NativePdfImageOcr(
      library: 'libtesseract.so',
      models: () => preparePdfOcrModels(storage),
    );
