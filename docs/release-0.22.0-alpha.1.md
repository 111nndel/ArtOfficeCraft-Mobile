# ArtOfficeCraft Mobile 0.22.0 — Practical editing across all four formats

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Word: added case-sensitive Find and Replace, navigation between matches and replace-one/replace-all with undo/redo.
- Excel: added named worksheet creation and restoration of the saved active sheet.
- PowerPoint: added slide reordering with model preservation, undo and redo.
- PDF: added undo/redo and page reordering, and fixed rotated-page fitting.
- Kept editing history bounded to 10 steps and 24 MiB per editor session.

## Known Limitations

- Find and Replace does not yet search Word table contents.
- Full Word layout, advanced spreadsheet styles and charts, PDF forms and some PPTX objects remain incomplete.
