# ArtOfficeCraft Mobile 0.34.0 — release build

> Android ARM64 development preview.

## What's New

- The public APK now uses Flutter release mode with Android debugging disabled.
- The build and publisher inspect the merged Android manifest before distribution.
- The existing application ID and preview certificate allow an in-place upgrade from 0.33.0. Android 16 QA covers the profile-to-release upgrade and reopens imported documents afterwards.

## Known Limitations

- Android runtime validation uses an x86_64 emulator. The public APK targets ARM64.
- OCR recognizes one PDF page at a time. Searchable OCR export remains in progress.
