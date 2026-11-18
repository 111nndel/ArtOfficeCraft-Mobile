# ArtOfficeCraft Mobile 0.57.0

## What's New

- Excel View / Manage sheets can rename the active sheet, move it left or right,
  hide it, show a hidden sheet, or delete it after confirmation. Hidden sheets no
  longer appear in the tab strip or normal sheet chooser. Reopening a saved XLSX
  restores its active visible sheet.
- Sheet actions reuse the pinned GridCraft command engine, including cross-sheet
  formula updates, defined-name scopes and workbook structure protection. The
  last visible sheet cannot be hidden or deleted. Pending cell input and a sheet
  action share one undo step; cancellation or failure retains the original book.
- Native Excel window responses move their owned cell maps, sheet list, selected
  cell and layout into the response. Full JSON window clones are removed without
  changing the cell/style protocol.
- The former separate add-sheet implementation now uses the same Rust commands.
  No new Kotlin, dependencies, plugins, permissions or native libraries.
  Processing remains local; the existing Android adapters are retained.
- App 0.57.0+64 (ARM64 versionCode 2064), native core 0.57.0, ABI 1.
  Reviewed engine pins remain WordCraft 0.18.1, GridCraft 0.19.1,
  DeckCraft 0.18.1 and PDFCraft 0.21.1.

## Known Limitations

- Sheet editing requires both book snapshots to fit the existing 24 MiB undo
  budget. New sheets are limited to 256 per workbook.
- Sheet duplication is not exposed: the current upstream copy command drops
  Excel table metadata and preserved embedded content.
- Deleting a referenced sheet produces #REF!, as expected; Undo restores it.
- Existing editor and format limits remain. APKs target Android ARM64 and use
  the existing development certificate. No Android frame-rate gain is claimed
  for the removed native JSON copies.
