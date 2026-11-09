# Platform boundaries

ArtOfficeCraft Mobile is intended to become cross-platform. Android is currently
the only packaged application target. Shared source and tested native document
operations do not establish that the entire UI works on another OS.

## Contracts

| Boundary | Shared API | Current implementations |
| --- | --- | --- |
| Native core | `openNativeCore`, `DocumentBackend` | Bundled Rust library, ABI 1; ordered Dart isolates |
| Open/export | `DocumentFiles` | Existing Android/iOS file-dialog plugin, isolated in `lib/platform/document_files.dart` |
| Storage | `ApplicationStorage` | Existing Android channels; portable directory-backed Dart storage |
| PDF display/OCR | `PdfPageRenderer` | Android PdfRenderer and offline OCR channel |
| Spreadsheet clipboard | `SystemClipboard`, `GridClipboard` | Android identity-bearing clipboard; Flutter text-only fallback |

`ArtOfficeCraftApp` accepts storage, file, PDF-renderer and clipboard services and passes
them through Home to the editors. A new platform entry point can supply these
without changing document editing or save guards. Directory storage needs an
application support directory supplied by that entry point. It does not guess a
user folder or require another plugin.

Android keeps the existing directory, filenames and reading-preference keys, so
upgrades do not relocate recent files, drafts, appearance or language choices.
The directory-backed adapter stores reading preferences as small JSON files,
serializes writes and rejects path-like format identifiers.

`GridClipboard` owns an immutable, bounded workbook snapshot in Dart and orders
reads/writes through an injectable `SystemClipboard`. Android exports selected
text and a random entry identity; workbook bytes stay private. Text equality
alone never authorizes formulas or formatting. The Flutter fallback has no entry
identity, immediately releases rich snapshot data and offers text-only paste.
Clearing a pending copy cannot resurrect its snapshot. An editor closed while
native copying is pending cannot overwrite a more recent copy from another file.

## Native packaging contract

| Platform | Core location |
| --- | --- |
| Android | `libartoffice_core.so`, supplied by the app's native library namespace |
| Linux | `lib/libartoffice_core.so` beside the executable |
| Windows | `artoffice_core.dll` beside the executable |
| macOS | `Contents/Frameworks/libartoffice_core.dylib` inside the app bundle |
| iOS | Core symbols statically linked and exported into the application process |

Desktop automatic lookup uses the resolved executable location rather than the
current directory or document directory. Explicit library paths remain available
for native tests. Missing libraries, incompatible ABI or missing engine symbols
disable the corresponding backend without starting a worker.

CI compiles a standalone Dart AOT executable on Linux, places the real host core
in its bundle location, changes to `/tmp` and runs all four document workers.
The smoke check creates, edits, saves and reopens DOCX, XLSX, PPTX and PDF. It
also reads native build information using automatic discovery. This checks the
FFI/worker layer; it does not launch a Linux Flutter app or render PDF pages.

## Remaining work

- Add native desktop/iOS runner projects, packaging and builds.
- Supply each target's application support directory and native file dialogs.
- Implement identity-bearing desktop clipboards if rich cross-file paste is needed;
  validate them on actual desktop runners. Portable text paste is already isolated.
- Evaluate a portable PDF rasterizer/OCR integration using representative files,
  fidelity, peak memory and latency before adding a dependency.
- Exercise desktop text input, windows, keyboard shortcuts and large-screen UI.

Keep document engines pinned to reviewed source commits. Updating their source
is independent of platform adapters; engine binaries ship with the application.
The application does not require a server, account or online conversion service.
