# ArtOfficeCraft Mobile — Rust/Flutter integration checkpoint

Date: 2026-11-02. Android UI preview with real WordCraft DOCX and GridCraft XLSX operations.

## Source and provenance

Pinned upstream repositories:
- WordCraft v0.14.0, commit `5cd53f184aab11def13b7fced18727159b9bc96a`.
- GridCraft v0.15.0, commit `30b210b4ef03b30616923465efa70766cefba379`.
- DeckCraft v0.14.1, commit `ee39ff67816d0039143ec7c98ea604cefe0cd2e5`.
- PDFCraft v0.17.0, commit `7d78f3e14474b978be014715e0cc64895d77025a`.

All repositories are downloaded and checked against pinned SHAs; original ZIP files untouched.

## Actual Rust functionality currently connected

`native/artoffice_core/src/lib.rs` builds against the **real** `wordcraft-doc` and `wordcraft-docx` crates from the pinned WordCraft repository, with no manual reimplementation of DOCX parsing.

The binary C ABI offers:
- `ac_engine_abi_version`
- `ac_docx_create`: create an OOXML DOCX from a UTF-8 paragraph.
- `ac_docx_inspect`: parse DOCX and return structured JSON with main-story paragraphs and table count.
- `ac_docx_append_paragraph`: parse input DOCX, append a paragraph with WordCraft model, and return output DOCX bytes.
- `ac_result_free`: free Rust-owned buffers from Dart.

Memory/error boundary: input size limits, UTF-8 validation, catch_unwind on exports, result status and explicit buffer destructor. ABI tested from Dart on Windows with a DLL and built for Android arm64.

Flutter screen `lib/native/native_word_screen.dart` uses system Android file dialogs to pick an existing file and to **save a new copy**; it does not silently overwrite originals. It displays a text-only WordCraft preview and supports appending a new paragraph, creating documents, and saving a copy.

**Do not misrepresent this as a complete DOCX editor.** Original formatting, page layout, tables and images are not rendered on the mobile screen. They are read/written by the WordCraft document model where supported, but round-trip fidelity for complex files remains unverified. Existing paragraphs are not yet editable on this screen.

## GridCraft XLSX (0.3.0)

Pinned GridCraft 0.15.0 crates gridcraft-core, gridcraft-model,
gridcraft-xlsx and gridcraft-calc are linked in native Android Rust.
The new FFI exports ac_xlsx_create, ac_xlsx_inspect, ac_xlsx_set_cell.
GridCraft reads and writes actual XLSX bytes; a JSON request updates A1
cell input in a specified sheet and recalculates formulas before saving.

Flutter has a native_grid_screen with open/create/edit/Save As and sheet
switching. Only 55 rows and 12 columns are visible; JSON inspection is
limited to 1600 stored cells per sheet. No chart/style image fidelity has
been established. Protected sheets refuse editing. Originals remain
untouched through the Android save-as dialog.

FFI smoke tested on Windows: A1=12, B1=8, C1=SUM(A1:B1)
then reopened as XLSX; displayed result 20. Physical Android device
testing is still pending.

## Not implemented yet

- Full GridCraft XLSX formatting/rendering and compatibility regression testing.
- DeckCraft PPTX FFI, slides editing/rendering and file I/O.
- PDFCraft PDF FFI, rendering/annotations and file I/O.
- Pixel-perfect WordCraft layout renderer and full Word formatting.
- Comprehensive document fidelity tests on complex real files.
- Signature/release packaging, real-device test, performance benchmarks, crash recovery.

The slides and PDF screens remain demonstration UIs; Excel now uses GridCraft.

## Upstream updates integration

Run `python tools/sync_native_pins.py` before native compile. It checks pinned repositories, exact Git commits and dirty files, then rewrites WordCraft and GridCraft path dependencies in `native/artoffice_core/Cargo.toml` to match `upstream/engines.lock.json`. If a pin changes, `stage-rust-engines.ps1` must download the approved version first.

`native/build_android_arm64.ps1` now verifies pins, builds the Android library with the NDK ARM64 linker, and copies it to `android/app/src/main/jniLibs/arm64-v8a/libartoffice_core.so`.

`build_native_preview.ps1` performs Rust rebuild, Flutter tests, ARM64 debug APK build and copies a validation APK to Downloads. New upstream source is never executed automatically merely because a GitHub tag appeared.

## Verification commands

```powershell
cargo test --manifest-path native/artoffice_core/Cargo.toml --lib
cargo build --manifest-path native/artoffice_core/Cargo.toml --release
dart run tools/smoke_word_ffi.dart native/artoffice_core/target/release/artoffice_core.dll
dart run tools/smoke_grid_ffi.dart native/artoffice_core/target/release/artoffice_core.dll
flutter analyze
flutter test
powershell -ExecutionPolicy Bypass -File native/build_android_arm64.ps1
powershell -ExecutionPolicy Bypass -File build_native_preview.ps1
```

Testing with an actual Android phone via ADB remains outstanding.

## Constraints

APK is debug and currently ARM64 only. It must not be represented as a finished office suite. Full features require significant engineering and tests, not just exposing existing Rust source trees.
