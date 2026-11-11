# ArtOfficeCraft Mobile 0.48.0-alpha.1

## What's New

- PDF OCR consumes the page image produced by the Rust renderer. Successful Rust
  rendering no longer opens, reparses or writes another PDF into Android's
  compatibility renderer solely for recognition.
- Image recognition is independently injectable through the shared Dart contract.
  The existing offline Tesseract runtime and bundled Russian/English models are
  reused without adding runtime libraries, Flutter plugins or Rust dependencies.
- Image decoding has byte, dimension and pixel limits. Closing a document during
  rasterization prevents OCR from starting; late recognition results are discarded.
- Android QA requires Russian/English recognition, copy, searchable saved text and
  undo/redo with the Android PDF fallback disabled, and checks malformed and
  oversized image rejection without opening a PDF.

## Known Limitations

- Android compatibility PDF rendering remains available when Rust rejects a page;
  fallback rendering is also usable before image OCR for such documents.
- The OCR adapter still uses Android BitmapFactory and Tesseract4Android. Tesseract,
  Leptonica and their native image libraries remain C/C++ components inside the APK.
  This release does not provide a pure-Rust OCR engine or desktop OCR packaging.
- OCR is page-based and may make mistakes; recognition quality varies by document.
- Rust engine versions and the native core remain those of 0.47.0. No new Rust
  capabilities or measured device-wide speed improvement are claimed.
- This is an experimental preview signed with the existing development certificate.
