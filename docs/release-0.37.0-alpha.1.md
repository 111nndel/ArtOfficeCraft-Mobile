# ArtOfficeCraft Mobile 0.37.0

> Android ARM64 development preview.

## What's New

- Upgrade the original Rust sources to WordCraft 0.16.0, GridCraft 0.17.0, DeckCraft 0.16.0 and PDFCraft 0.19.0.
- Integrate upstream import, serialization and document-model fixes through the existing mobile editors.
- Add an isolated GitHub Actions workflow for resolving updated engine dependencies, adapter checks and complete dependency notices.

## Known Limitations

- The mobile editors expose a subset of the original desktop engines' features.
- Android runtime validation uses an x86_64 emulator. The public APK targets ARM64.
