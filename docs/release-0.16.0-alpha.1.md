# ArtOfficeCraft Mobile 0.16.0 — Document worker and safer undo history

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Added long-lived background document workers for DOCX, XLSX, PPTX and PDF operations.
- Keep the previous document and pending user input if an edit fails; reuse validated snapshots within a worker.
- Route embedded PPTX image work through the document worker and release native buffers on editor close.
- Fixed Word undo restoration so a failed attempt does not consume a history step.
- Applied a shared 10-step / 24 MiB in-session undo/redo history budget.

## Known Limitations

- Native file parsing and serialization still occurred for many operations.
- The 55-by-12 spreadsheet viewport limit still applied to this release; full device coverage was incomplete.
