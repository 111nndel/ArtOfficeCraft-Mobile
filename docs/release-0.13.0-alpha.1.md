# ArtOfficeCraft Mobile 0.13.0 — Spreadsheet editing and formatting

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Commit spreadsheet input before saving or moving to another cell, without discarding the draft after native errors.
- Added undo and redo for cell values and styles.
- Save bold, italic, underline, font size and color, fills, borders, alignment, wrapping and basic number formats to XLSX.
- Preserve cell styling when changing values or formulas; fixed PDF document cleanup.

## Known Limitations

- The spreadsheet UI was still limited to 55 rows by 12 columns.
- Complex workbook fidelity and recovery of uncommitted input after process termination remained incomplete.
