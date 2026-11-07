# ArtOfficeCraft Mobile 0.32.0 — insert text into a PDF

> Android ARM64 development preview.

## What's New

- In PDF, open Edit → Insert text, enter text and choose a size. Select Choose position, then tap the page. You can zoom and pan before placing the text.
- Saved copies contain selectable page text in embedded Inter, with Latin and Cyrillic support. Placement uses the displayed page crop and rotation. Undo and redo work with the inserted text.
- If the text is too close to an edge, the editor keeps the draft so you can pick a new location or size.

## Known Limitations

- Insertion supports up to 1,000 characters with five size options and a single font. Unsupported characters are reported before writing.
- Text can be added over a scanned page. Recognizing and editing the scan's original words requires OCR.
- Android runtime validation uses an emulator.
