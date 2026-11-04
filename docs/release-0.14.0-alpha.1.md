# ArtOfficeCraft Mobile 0.14.0 — Recover work after app termination

> Android ARM64 development preview. This is not a stable or feature-complete office suite.

## What's New

- Added recovery drafts for Word, spreadsheets, presentations and PDF sessions.
- Restore unsaved paragraph or cell input, PPTX text dialogs and edited PDF page selection from the home screen.
- Keep drafts after cancelled saves and require confirmation before discarding them.
- Preserve original imported documents when removing a recovery draft.

## Known Limitations

- Only the last recorded draft can be restored; the final keystrokes may be missing after an abrupt process kill.
- Undo history does not persist between runs; the early spreadsheet bounds still applied.
