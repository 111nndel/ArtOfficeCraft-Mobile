# ArtOfficeCraft Mobile 0.36.0

> Android ARM64 development preview.

## What's New

- Find text within a PDF using **Reading → Search**. Search covers embedded text and invisible OCR layers and ignores letter case.
- Jump between results and see the matching text area highlighted. Search works in single-page and continuous reading modes.
- Search runs on the native worker in page batches. The panel shows progress and supports cancellation.
- The Android release uses the existing preview certificate and stays offline.

## Known Limitations

- Search lists up to 512 matching text regions. One region can contain several instances of the query.
- Image-only scans need an OCR layer. Search coverage depends on the PDF's text encoding and how its content is structured.
- Android runtime validation uses an x86_64 emulator. The public APK targets ARM64.
