# ArtOfficeCraft Mobile 0.27.0 — Excel range sorting

> Android ARM64 development preview.

## What's New

- Select a range in Excel and open Data → Sort. Choose its sort column, ascending or descending order, and whether to keep the first row as a header.
- GridCraft sorts the selected rows, moves cell styles with their contents and adjusts relative references in moved formulas. Undo and redo restore the corresponding workbook snapshots.
- The mobile core now uses the original WordCraft 0.15.2, GridCraft 0.16.1, DeckCraft 0.15.1 and PDFCraft 0.18.2 sources. Exact commits and bundled notices are recorded with the build.

## Known Limitations

- Sorting uses one key and covers up to 4,096 cells and 128 columns. The original workbook and sorted result must each fit the existing 24 MiB undo budget.
- Affected data rows must be unfiltered. Merged cells, array formulas, in-cell pictures and pivot results are guarded. For a structured table, select its full column span and keep its header and totals outside the sorted rows.
- Android runtime validation uses an emulator.
