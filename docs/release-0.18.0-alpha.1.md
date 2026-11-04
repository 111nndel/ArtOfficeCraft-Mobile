# ArtOfficeCraft Mobile 0.18.0 — File selection and touch-resizable spreadsheets

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Fixed Android file-picker filters for DOCX, XLSX, PPTX and PDF in all entry points.
- Displayed imported row heights, column widths, hidden rows/columns, merged cells and supported spreadsheet formatting.
- Added touch-and-drag resizing for row and column headers with XLSX persistence and undo/redo.
- Extended spreadsheet pinch zoom to 500% while keeping compact sheet headings.

## Known Limitations

- Legacy DOC/XLS/PPT files were not supported.
- Conditional styles, charts, images, frozen panes and auto-fit remained incomplete; complex workbooks could use substantial processing.
