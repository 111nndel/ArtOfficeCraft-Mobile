# ArtOfficeCraft Mobile 0.25.0 — Spreadsheet rows and columns

> Android ARM64 development preview.

## What's New

- Open Home, then Rows and columns. Insert entire rows above the selection or entire columns to its left. A rectangular touch selection supplies the number of lines.
- Delete rows or columns through an in-panel confirmation that lists the affected lines, including cells beyond the visible area.
- GridCraft shifts values, styles, hidden lines, sizes and merges. It adjusts supported formula references across sheets and named ranges. A reference to a deleted cell becomes `#REF!`.
- Structural edits apply pending input first, support undo and redo and save into a real XLSX copy. The sheet retains its zoom.
- Selecting an exact range dismisses the keyboard so the selected cells remain visible.
- The Android 16 release gate includes row and column scenarios through the mobile UI and the real Rust engine.

## Known Limitations

- An operation covers at most 256 contiguous rows or columns. The workbook and result must each fit the 24 MiB undo budget.
- Protected sheets and workbooks are read-only for these commands. Insertions that would push populated cells, explicit line geometry or merged ranges beyond the worksheet are refused.
- Complete compatibility with advanced workbook objects and formulas is still in progress. The four upstream pins remain the same as 0.24.0.
- Word, PowerPoint and PDF receive regression coverage in this release. Physical Vivo testing is outstanding.
