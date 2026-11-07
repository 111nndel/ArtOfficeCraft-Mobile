# ArtOfficeCraft Mobile 0.28.0 — Excel value filters

> Android ARM64 development preview.

## What's New

- Select a header and data rows in Excel, then open Data → Filter. Choose a column and check the values or blank cells to show.
- Apply criteria to multiple columns of the same range. Remove AutoFilter to reveal the rows. Both actions support undo and redo.
- Save a copy to persist worksheet AutoFilter and row visibility in XLSX. Reopen the Filter panel to see the saved choices.

## Known Limitations

- The mobile filter edits one ordinary worksheet AutoFilter range per sheet. The selected range starts with a header and has up to 4,096 data rows and 128 columns. Each column supports up to 512 distinct choices within a bounded payload.
- Editing structured Excel table filters, custom criteria, merged ranges and grouped or independently hidden rows is outside this preview.
- Android runtime validation uses an emulator.
