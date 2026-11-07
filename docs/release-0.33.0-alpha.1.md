# ArtOfficeCraft Mobile 0.33.0 — offline PDF scan recognition

> Android ARM64 development preview.

## What's New

- In PDF, choose Edit → Scan and OCR → Recognize page. Review, select or copy the recognized Russian and English text. The current page is rendered and recognized on the Android background worker.
- The APK bundles Tesseract4Android 4.9.0, Russian and English models and their notices. The build checks their hashes and the app works without network access.
- Retrying PDF text placement clears the warning from the previous attempt.

## Known Limitations

- OCR covers one page at a time and returns text to the tool panel. Adding a searchable text layer to the saved PDF remains future work.
- Recognition quality depends on the scan. Handwriting and complex page layouts can produce errors.
- Android runtime validation uses an emulator.
