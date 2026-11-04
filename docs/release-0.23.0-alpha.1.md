# ArtOfficeCraft Mobile 0.23.0 — Spreadsheet range selection and Word formatting

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Excel: added rectangular touch-range selection with accessible 44 dp handles and edge auto-scrolling.
- Added exact-range entry (for example A1:D10), including merged-cell handling, while retaining ordinary 10-500% sheet zoom.
- Applied formatting or Clear Contents across selected cells (up to 4,096 cells per operation), with recalculation and undo.
- Word: added selected-text color, automatic font-color reset and left paragraph indentation options.
- Fixed the displayed line-spacing multiplier without introducing a separate editing screen.

## Known Limitations

- Complex Word page layout, advanced spreadsheets and charts, exact PPTX object rendering and PDF forms remain incomplete.
- PowerPoint and PDF did not gain new editing features in this release.
