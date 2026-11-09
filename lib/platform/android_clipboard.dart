import 'package:flutter/services.dart';

import 'system_clipboard.dart';

/// Only selected text and an opaque token leave the process. Workbook bytes
/// remain in the shared Dart clipboard session.
final class AndroidSystemClipboard implements SystemClipboard {
  const AndroidSystemClipboard();
  static const channel = MethodChannel('artofficecraft/grid_clipboard');

  @override
  bool get supportsIdentity => true;

  @override
  Future<void> write(SystemClipboardContents contents) =>
      channel.invokeMethod<void>('write', {
        'text': contents.text,
        'token': contents.token,
      });

  @override
  Future<SystemClipboardContents?> read() async {
    final value = await channel.invokeMapMethod<String, dynamic>('read');
    final text = value?['text'];
    if (text is! String) return null;
    final token = value?['token'];
    return (text: text, token: token is String ? token : null);
  }
}
