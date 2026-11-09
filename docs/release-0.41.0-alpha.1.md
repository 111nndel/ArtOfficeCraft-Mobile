# ArtOfficeCraft Mobile 0.41.0

> Android ARM64 development preview.

## What's New

- Updated the bundled, source-pinned document engines: WordCraft 0.17.0, GridCraft 0.18.0, DeckCraft 0.17.0 and PDFCraft 0.20.0.
- Resolved the native dependency lock against these exact releases and refreshed the bundled licence notices.
- The native core now reports version 0.41.0; its existing C ABI remains version 1.
- Engine-refresh branches now run the existing PDF image-comparison workflow, using the same original six-page fixture and fixed comparison policy.
- Removed the unused Cupertino icon dependency and template configuration clutter. No new application-side editor classes or Kotlin handlers were added.

## Known Limitations

- Upstream desktop features do not automatically become tools in the mobile editors. This refresh updates their processing libraries; the approved mobile interface is unchanged.
- PDFCraft's text-editing library now includes compiled Unicode segmentation data. The application still works offline; this adds local dependencies rather than a service.
- The packaged PDF viewer still uses Android PdfRenderer and local OCR. The Rust CPU renderer is still under evaluation and is not selected in the application.
- Android remains the only packaged UI target. Linux native-worker checks do not establish a working desktop Flutter application.
- Android runtime checks use an x86_64 emulator. The downloadable APK targets ARM64; physical-device validation remains separate.
