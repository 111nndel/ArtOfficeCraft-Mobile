# ArtOfficeCraft Mobile 0.46.0

> Android ARM64 development preview.

## What's New

- Selecting a loaded cell updates the formula bar locally. Empty cells use the exact default style supplied by Rust; merged cells retain their anchor and formatting. Pending edits still pass through the existing guarded commit before selection changes.
- Progress overlays the spreadsheet instead of inserting space below the sheet tabs. Cell reads and writes no longer displace the formula bar, sheet tabs or viewport.
- Recently read spreadsheet regions remain available when panning back horizontally or vertically. Read-ahead follows visible row/column geometry, including hidden runs, and requests start during movement rather than waiting for a pause. Only one viewport read runs at a time.
- The cache belongs to one immutable workbook snapshot and sheet. Edits, undo and sheet changes invalidate it. Late responses cannot overwrite a newer selection, pending formula input or edited workbook.
- Native core 0.46.0, ABI 1. The four engine pins and 219-package Rust dependency graph are unchanged. No new runtime package, Kotlin code or appearance setting is added.

## Known Limitations

- Recent-region retention is bounded to eight windows, 32,768 logical cell positions and two million input/display text units. A single larger active region remains complete. Old regions may be evicted; edits and sheet changes intentionally clear cached data.
- Newly visited uncached areas still require a background read and may briefly show empty cells on fast jumps. This change reduces repeated loading and reads ahead; it does not preload the whole workbook.
- Imported layout remains approximate, charts and complex styles are incomplete, and edits still serialize/reparse the workbook. No claim is made about FPS on a physical phone or an unprovided user workbook.
