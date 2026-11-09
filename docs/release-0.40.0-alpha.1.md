# ArtOfficeCraft Mobile 0.40.0

> Android ARM64 development preview.

## What's New

- Spreadsheet copying and pasting now use a shared Dart clipboard session with replaceable system adapters.
- Clipboard reads/writes execute in order; clearing a pending copy cannot restore an obsolete workbook snapshot.
- A closed spreadsheet editor cannot overwrite a newer clipboard entry after its native copy request completes.
- Android keeps rich range copying with formulas, formatting and an opaque clipboard-entry identity. Workbook bytes remain private.
- Added a standard Flutter text-only adapter for other native platforms. Equal text from another app cannot reuse stale formulas or formatting.
- Extended the Linux native-worker smoke check to copy/paste a formula through the shared clipboard model and reopen the result.
- Built and measured the pinned upstream PDFCraft CPU renderer in a separate development workflow. Results and limitations are recorded in `docs/pdf-renderer-evaluation.md`.
- Added no application runtime dependencies or online services. All four engine pins remain at their latest reviewed stable releases.

## Known Limitations

- Android remains the only packaged UI target. Other platforms need runner and file/PDF integration work.
- The standard Flutter clipboard adapter transfers text; identity-bearing desktop adapters are needed for rich range paste.
- The PDF probe used one synthetic file on Linux and does not establish complex-document fidelity or Android performance. The APK retains Android rendering.
- Android runtime checks use an x86_64 emulator. The downloadable APK targets ARM64; physical-device testing remains separate.
