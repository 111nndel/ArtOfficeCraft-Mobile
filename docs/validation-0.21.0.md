# ArtOfficeCraft Mobile 0.21.0 validation

## Regression fixes

The 0.20 sheet overview replaced the editable sheet below 25%, centered used
bounds, removed surrounding empty cells and zoomed on tap. It and both fit
controls have been removed. The normal sheet now supports 10–500% zoom, full
Excel coordinate bounds, empty-cell selection and editing without changing zoom.
Pinch preserves its document anchor; pan inertia and touch resizing remain.
Headings follow sheet edges unless explicitly pinned.

Below 50%, a viewport-sized painter avoids building thousands of tiny widgets.
It uses the same exact visible-window response, paints empty gridlines according
to the workbook setting, respects merges/styles and uses normal hit-testing.
There is no thumbnail state or sampling. Native queries are limited to 262,144
intersections and 8,192/2,048 visible row/column indices; text is not truncated.
Whole-XLSX parsing per query/edit remains a performance limitation.

Recent-file loss was caused by reusing a workspace id after an editor opened or
created another document. That overwrote the previous app-private copy and list
entry. Successful replacement now starts a separate identity in all four editors;
cancellation/failure leaves it intact. Editing/export still update the current
copy. Original device files are not overwritten. This does not reconstruct copies
already replaced by older versions; reopen the original device file. Clearing
app data or automatically deleting files is not part of this fix.

## Completed checks

- Clean Flutter analysis; 118 unit/widget tests passed. Added checks cover low
  zoom, surrounding empty cells, bounded widget creation, unchanged zoom on
  tap/Go to cell, each editor's actual open command, cancelled pickers, stable
  recent-file identities, favorites and disk reload of both copies.
- 25 Rust tests passed. The replacement window test checks all 20,000 populated
  cells, long text without truncation and explicit rejection of excessive bounds.
- 11 Python updater/license tests passed.
- All nine public real-engine scenarios passed on Android 16 API 36 x86_64.
  The revised sheet case checks 10% scale, cell selection without zoom jumps,
  pending-input commit, actual Rust edit, Save As and reopening. The integration
  Save As dialog is mocked.
- An ordinary profile APK from lib/main.dart passed package/ZIP, native 16-KB
  alignment, bundled notices, offline permissions and unchanged certificate checks.
  Real DocumentsUI checks passed for all four MIME filters and XLSX import.
  Held-finger drag changed a column 404 to 543 physical pixels and a row 210 to
  120; Undo restored 210.

The public tools/test_recent_imports.js also exercises consecutive real SAF
imports from inside the editor, force-stop, both recent entries and reopening
both copies. It uses public QA files and a dedicated emulator only.

Tagged Actions independently checks Flutter/Python and Rust, rebuilds ARM64,
verifies the ordinary APK and signs it in the isolated environment. Actions does
not run Android emulator tests. Version 0.21.0+27 preserves the app id and signing
identity for updating previous previews.

## Limits

Physical Vivo Android 16 and an actual 16-KB-page runtime were unavailable.
Full Office layout/features, charts, conditional styles, document freeze panes,
automatic row sizing and persistent parsed Rust models remain unfinished.
Engine pins are unchanged: WordCraft 0.15.1, GridCraft 0.16.0, DeckCraft 0.15.0,
PDFCraft 0.18.1. The original vendored JBIG2 patch and offline license collection
remain. No private workbook or screenshot is committed.
