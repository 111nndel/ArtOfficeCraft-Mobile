# ArtOfficeCraft Mobile 0.26.0 — Touch reading for PDFs and slides

> Android ARM64 development preview.

## What's New

- Choose horizontal page turns, vertical page turns, or a continuous vertical strip. In PDF use Reading → Reading mode. In presentations use View → Reading mode.
- Swipes within a zoomed or tall page pan it. A swipe toward the next or previous page turns at the corresponding edge.
- Pinch to zoom in single-page or continuous mode. The continuous reader mounts visible pages and updates the page or slide indicator as you scroll.
- The current page stays selected when you change modes. PDF and presentation mode choices are stored separately in Android's private settings.

## Known Limitations

- DOCX currently uses continuous editable text. True DOCX pagination requires the WordCraft layout integration.
- PDF remains a rendered page view. Advanced document and presentation fidelity is still in progress.
- Android runtime validation uses an emulator.
