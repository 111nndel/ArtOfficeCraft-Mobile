import 'dart:io';

import '../native/grid_clipboard.dart';
import 'android_clipboard.dart';
import 'flutter_text_clipboard.dart';

/// One application session outlives individual editor screens. Other platform
/// entry points can inject a richer adapter without changing the grid editor.
final defaultGridClipboard = GridClipboard(
  Platform.isAndroid
      ? const AndroidSystemClipboard()
      : const FlutterTextClipboard(),
);
