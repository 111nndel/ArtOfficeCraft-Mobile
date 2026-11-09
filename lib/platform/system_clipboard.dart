typedef SystemClipboardContents = ({String text, String? token});

/// A token identifies the actual system clipboard entry, not just equal text.
/// Adapters without that capability return null, enabling text-only paste.
abstract interface class SystemClipboard {
  bool get supportsIdentity;
  Future<void> write(SystemClipboardContents contents);
  Future<SystemClipboardContents?> read();
}
