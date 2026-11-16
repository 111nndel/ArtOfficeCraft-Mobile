# ArtOfficeCraft Mobile 0.51.0-alpha.1

## What's New

- Android recognizes the app as a viewer for DOCX, XLSX, PPTX and PDF files.
  Files opened from Downloads, file managers or the share sheet are routed to
  the matching editor, including cold and already-running application launches.
- Specific MIME filters make the app eligible for Android's persistent handler
  choice. The app does not claim unrelated file types or web URLs.
- Incoming files are bounded read-only copies. Temporary URI grants are used
  without broad storage permissions; copies are released after Dart reads them.
  A previous editor and its unsaved draft remain available through Back.
- Word inserts an empty paragraph before or after the current paragraph, inherits
  paragraph formatting, and supports the existing save, undo, redo and recovery
  paths. The existing append-at-end command is in the same insertion group.
- Long paragraph drafts reuse one immutable text style per run instead of
  constructing the same style for every UTF-16 code unit.
- No new dependencies or engine revisions. The Android-specific code only adapts
  URI grants; format selection and navigation remain in Dart. Core version 0.51.0.

## Known Limitations

- Android chooses how and when to offer a default-app selector. A file source
  must provide a supported MIME type and a readable local URI.
- Legacy DOC, XLS and PPT formats are not advertised as supported handlers.
- Incoming documents open as working copies; saving uses an explicit destination.
- Full DOCX layout fidelity and device-wide FPS gains are not claimed.
- Preview release signed with the existing development certificate.
