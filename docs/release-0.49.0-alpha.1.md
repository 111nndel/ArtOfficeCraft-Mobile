# ArtOfficeCraft Mobile 0.49.0-alpha.1

## What's New

- PDF page images are recognized through a shared Rust/Dart adapter to the bundled
  Tesseract C API. The Kotlin OCR class, Android OCR method channel and Java OCR
  wrapper dependency are removed.
- Rust owns bounded PNG decoding, white transparency compositing, Russian/English
  recognition and normalized word/line bounds. A separate OCR worker keeps PDF
  rendering independent and drains native calls before termination.
- Tesseract engines, iterators, result strings and image memory are released after
  every request. Concurrent calls are serialized to bound native OCR memory.
- Dart stages the same offline model assets into app-owned storage, reuses valid
  copies and repairs incomplete files with ordered atomic writes.
- No new Rust packages, Flutter plugins or OCR models are introduced. Existing
  Tesseract/Leptonica/image binaries are reused and their notices retained.
- CI covers the same OCR worker on Linux with real Tesseract and app model files,
  plus Android recognition, copying and saved searchable PDF text with no Android
  PDF fallback, malformed/oversized images, undo/redo and ordinary-app checks.

## Known Limitations

- Tesseract and its image libraries remain C/C++. Their packaged Android binaries
  still contain unused JNI exports; the application does not call those exports.
- Desktop/iOS application runners and OCR binary/model packaging are not supplied.
  Linux AOT integration checks do not establish full desktop UI support.
- OCR remains page-based and may make mistakes. Device-wide performance gains
  and recognition accuracy beyond the tested fixtures are not claimed.
- Android PDF rendering remains available as a compatibility fallback.
- Preview release signed with the existing development certificate.
