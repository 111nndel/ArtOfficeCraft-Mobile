import 'package:flutter/services.dart';

import 'system_clipboard.dart';

/// Flutter's standard clipboard is portable but exposes no entry identity.
/// Equal external text must therefore never revive a rich workbook snapshot.
final class FlutterTextClipboard implements SystemClipboard {
  const FlutterTextClipboard();

  @override
  bool get supportsIdentity => false;

  @override
  Future<void> write(SystemClipboardContents contents) =>
      Clipboard.setData(ClipboardData(text: contents.text));

  @override
  Future<SystemClipboardContents?> read() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data == null ? null : (text: data.text ?? '', token: null);
  }
}
