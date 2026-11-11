# ArtOfficeCraft Mobile 0.47.0

> Android ARM64 development preview.

## What's New

- Excel Home / Cell format / Merge cells adds merge, merge-and-center and unmerge. Select cells with the existing touch handles or enter a range in the same tool pane.
- A merge keeps the upper-left cell. Other occupied cells are counted across the whole selection, including hidden/offscreen cells and empty-looking formulas. Clearing them requires confirmation; cancelling retains the draft and workbook. Rust independently checks that consent before clearing content.
- Pending cell input and the merge/unmerge are one checked native transaction and one undo step. A failed edit or preview retains the pending text. Styles, dimensions and merged geometry survive saving and reopening. Repeating merge-and-center keeps the range merged.
- Confirmation reuses cached records when they cover the selection. Otherwise at most two bounded read windows use the existing workbook reader. No whole-workbook inspection or extra serialization is needed for the preview.
- Native core 0.47.0, ABI 1. The four engine pins and 219-package Rust graph remain unchanged. No new runtime dependency, Kotlin code or appearance setting is added.

## Known Limitations

- At most 4096 cells per operation. Only complete existing merged regions may be changed; touch/range selection expands to include intersecting merges.
- Protected sheets/workbooks, structured Excel tables and array/spill ranges are excluded. Merge/unmerge requires the input and result to fit the existing 24 MiB undo budget.
- Unmerge restores cell boundaries, not contents cleared by a confirmed merge. Use Undo to restore the previous contents. Merging does not concatenate text.
- Imported layout remains approximate. Edits still serialize/reparse the workbook; emulator checks do not establish physical-phone FPS.
