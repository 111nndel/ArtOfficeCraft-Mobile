# ArtOfficeCraft Mobile 0.24.0 — Spreadsheet clipboard

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Excel: copy a cell or rectangular selection, then paste into another location, sheet or workbook in the same app session.
- Paste all retains supported formatting and rebases relative formula references. Values, formulas and formatting can also be pasted separately.
- Paste tab-separated text from other Android apps, including quoted tabs, line breaks and Unicode, while retaining destination formatting.
- Pending input is committed before copying; paste uses checked native snapshots, undo/redo and normal XLSX export.
- Preserved the approved nested mobile tool panel and ordinary editable 10–500% sheet zoom.
- Added real Android clipboard regression scenarios to the cloud Android 16 gate; previews can now be built, checked and published without a contributor PC.

## Known Limitations

- Rich clipboard data lasts only for the current app process. Only selected text and an opaque identity token enter Android's system clipboard; the source workbook snapshot stays in app memory.
- Copy/paste is bounded to 4,096 cells, 256 KiB of UTF-8 text and a 24 MiB source workbook. Protected destinations, partial merges, array/spill ranges and format-only merged sources are rejected.
- Cut, transpose, cross-app rich Office clipboard and complete chart/conditional-format fidelity are not implemented.
- Word, PowerPoint and PDF gain no new editing feature in this release; their existing regression scenarios still run.
- The four upstream source pins are unchanged. The original GridCraft command engine is newly linked; its additional dependency notices are included.
- A cloud Android 16 emulator does not establish compatibility with every physical Vivo or an actual 16 KiB-memory-page device.
