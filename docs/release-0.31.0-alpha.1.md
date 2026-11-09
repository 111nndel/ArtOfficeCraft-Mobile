# ArtOfficeCraft Mobile 0.31.0 — PDF page text editing

> Android ARM64 development preview.

## What's New

- In PDF, open Edit → PDF text and choose a paragraph on the current page. Apply changes, review the page and save a copy. The PDF contains the rewritten page text and supports undo and redo in the editor.
- The tool uses the existing PDFCraft 0.18.2 pin and reads text only when requested for a page. It checks that the source text still matches before replacing it.

## Known Limitations

- Scans and invisible OCR text require separate tools. Complex layouts and PDF font encodings can limit which paragraphs the engine can rewrite. A replacement can reflow within its paragraph.
- The tool lists up to 256 supported blocks on one page. It edits existing text. New text boxes, images, form filling and OCR remain in progress.
- Android runtime validation uses an emulator.
