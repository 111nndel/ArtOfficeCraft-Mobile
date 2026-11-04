# ArtOfficeCraft Mobile 0.20.0 — Spreadsheet overview and gesture changes

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Aligned row and column headings with the sheet edges and added an explicit option to pin headings.
- Introduced whole-sheet and fit-to-width overview options based on the used range.
- Improved pinch-zoom origin, inertial scrolling and resizing of rows or columns by dragging their headings.
- Used a bounded overview renderer for heavily zoomed-out worksheets.

## Known Limitations

- Historical release: the separate overview modes introduced here were removed in v0.21.0 because of usability regressions.
- Charts, conditional formatting and other advanced features remained incomplete.
