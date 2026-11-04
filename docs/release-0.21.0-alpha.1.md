# ArtOfficeCraft Mobile 0.21.0 — Restore the normal spreadsheet and recent files

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Removed the separate XLSX thumbnail/overview mode and retained a normal editable sheet at 10-500% zoom.
- Kept surrounding empty cells visible and preserved tap-to-select behavior at different scales.
- Made visible-cell rendering precise and bounded while retaining touch pan, zoom and compact headings.
- Fixed document-session identity reuse that caused recently opened files to disappear from history.

## Known Limitations

- Working copies overwritten by earlier buggy versions cannot be reconstructed from app history; reopen the original file.
- Charts, conditional formatting and complete Office compatibility were still in progress.
