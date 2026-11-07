# 0.10.0 development preview validation — 2026-11-03

## Changes

- File parsing, native edits, formula recalculation and serialization run in worker isolates.
- DOCX plain paragraphs can be changed, with selected character formatting,
  alignment and line spacing; undo/redo uses bounded document snapshots.
- XLSX caches its inspected cell map once per update and creates visible rows lazily.
- Touch commands adapt to larger text; short screens and keyboard insets hide
  secondary panels. PPTX text objects have a list with large touch targets.
- Native binary metadata records exact upstream pins. Rust licenses for 94
  resolved packages are bundled in the About / Licenses screen.
- Source verification rejects untracked compiler inputs as well as tracked edits.
- A checked GitHub prerelease upload script transfers APKs directly from the
  build machine, without relaying their contents through chat.

## Results

| Check | Result |
| --- | --- |
| Flutter analysis | No issues |
| Flutter widget/unit tests | 42 passed |
| Rust tests | 13 passed |
| Source updater tests | 4 passed |
| Android 16 API 36 x86_64 emulator | Native four-format integration passed |
| DOCX in Android UI | Edit existing text, undo, redo |
| XLSX in Android UI | Change A1 from 12 to 15; SUM(A1:B1) changes from 20 to 23 |
| PPTX / PDF in Android UI | Added text displayed; duplicated PDF rendered with two pages |
| Android filesystem | Write, flush, read and parse DOCX/XLSX/PPTX/PDF again |
| ARM64 optimized profile APK | Built; ZIP integrity and signature verified |
| APK / ELF alignment | All packaged native libraries pass 16-KiB checks; zipalign passes |
| Final merged APK permissions | No INTERNET or Wi-Fi access permission |
| Development certificate | Same SHA-256 certificate as the delivered 0.9.0 APK |

The emulator runs with 4096-byte pages. Runtime testing on 16-KiB hardware and
on the user's Vivo has **not** been performed. The native integration test uses
a separate debug test APK; the downloadable preview uses optimized profile mode
with the existing development certificate. The test-only VM-service permission
is restored afterward and is absent from the downloadable APK.

The interactive Android Save As picker was not retested in this 0.10.0
integration scenario. The filesystem roundtrip is a distinct check. These are
small generated test files, not a broad document fidelity or large-file benchmark.

## Remaining work

This is not full Microsoft Office or Adobe feature parity and does not yet
fully implement the approved mockup. DOCX uses a paragraph editor and a simplified
flow preview, not a complete page layout engine with inline cursor editing.
Tables, floating objects and complex styles are not fully rendered. Protected,
tracked-revision and object-bearing paragraphs are intentionally read-only.

XLSX display is still bounded to 55 rows × 12 columns and 1600 inspected populated
cells per sheet. PPTX geometry, themes and advanced objects are approximate.
PDF organization and rendering work, while rich PDF text editing, forms and
signatures are incomplete. Import/export may not preserve every unsupported
format feature; Save As writes a new copy. Each edit still serializes the file,
and large documents need a persistent native model and performance profiling.
