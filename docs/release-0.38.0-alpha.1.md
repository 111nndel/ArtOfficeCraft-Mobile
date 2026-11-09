# ArtOfficeCraft Mobile 0.38.0

> Android ARM64 development preview.

## What's New

- **Home → Find** searches displayed cell values or formulas on the current sheet or across the workbook. Search ignores case.
- Move between results with large touch controls. The editor reveals distant cells and switches sheets while retaining zoom.
- Starting a search commits pending cell input. Moving to another result after typing refreshes the results. Search uses the existing undo history for edits.
- Search walks sparse native cells in bounded background batches with progress and cancellation.
- Hidden formulas on protected sheets stay concealed in both search and the cell input bar.

## Known Limitations

- Search lists up to 512 matching cells and treats the query as literal text.
- Hidden cells are included and marked in the result bar.
- Formula values use their saved calculation results.
- Android runtime validation uses an x86_64 emulator. The public APK targets ARM64.
