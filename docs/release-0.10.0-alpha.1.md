# ArtOfficeCraft Mobile 0.10.0 — Initial offline Android preview

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Introduced an ARM64 Android 7+ development build with Flutter UI and Rust-backed document operations.
- DOCX: edit existing paragraphs, apply basic formatting, and undo or redo changes.
- XLSX: render rows lazily instead of copying the entire cell map for each cell.
- Improved large-text and landscape layouts; added PPTX text-object navigation.
- Displayed bundled engine versions and licence information inside the app.

## Known Limitations

- This is an early development preview, not a finished Office replacement.
- The physical-device and 16 KiB page-size runs were not completed for this release.
