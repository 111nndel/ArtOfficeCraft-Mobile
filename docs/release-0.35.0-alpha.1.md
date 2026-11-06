# ArtOfficeCraft Mobile 0.35.0

> Android ARM64 development preview.

## What's New

- Add a searchable text layer after recognizing a scanned PDF page in Russian or English. The layer is invisible and the scan stays in place.
- Save the edited PDF as a copy. PDF readers that support text search and selection can use the recognized words.
- Adding a layer supports undo and redo. Pages that already contain searchable text are protected against a second layer.
- OCR continues to run offline with the models bundled in the APK. The release uses the established preview certificate.

## Known Limitations

- Recognize and add the layer one page at a time. Accuracy depends on the scan and the language.
- Android runtime validation uses an x86_64 emulator. The public APK targets ARM64.
