# ArtOfficeCraft Mobile 0.61.0

## What's New

- Updated WordCraft and DeckCraft to 0.19.1 and PDFCraft to 0.22.0. GridCraft uses its current stable release, 0.19.1. The sources and dependencies are pinned.
- PowerPoint can edit speaker notes in Slide Show / Notes. Edits are undoable and saved in the exported PPTX. Untouched text keeps its formatting.
- Browsing a long PDF retains recent thumbnails instead of flushing them all at the cache limit. PowerPoint renders its slide shapes without rebuilding copies of their data on each repaint.
- Android unregisters workspace, reading and clipboard handlers when a Flutter engine detaches.
- App 0.61.0+68, Android ARM64 versionCode 2068. Native core 0.61.0, ABI 1.

## Known Limitations

- The speaker notes editor handles up to 64 KiB of text per slide, within a 2 MiB text budget per presentation. Oversized notes are preserved on export.
- The Android preview targets ARM64 devices.
