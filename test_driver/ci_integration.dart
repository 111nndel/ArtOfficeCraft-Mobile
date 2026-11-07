import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Screenshots travel through the integration driver before Android uninstalls
// the test app. No root access or polling of app-private files is required.
Future<void> main() async {
  final output = Directory(
    Platform.environment['AOC_SCREENSHOTS'] ?? 'build/android-qa/screenshots',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name) ||
          bytes.length < 24 ||
          bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
        return false;
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
      return true;
    },
    // PNGs are saved separately; do not duplicate their byte arrays in JSON.
    responseDataCallback: null,
  );
}
