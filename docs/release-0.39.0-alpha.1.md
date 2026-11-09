# ArtOfficeCraft Mobile 0.39.0

> Android ARM64 development preview.

## What's New

- Removed the Android-only gate from Rust document loading. All four bridges and build information share the same checked loader.
- Isolated file opening/export behind `DocumentFiles`; editors retain their existing pending-input and cancelled-save behavior.
- Isolated settings, recent files, recovery drafts and reading preferences behind `ApplicationStorage`. A directory-backed implementation uses only Dart file I/O.
- Separated the PDF renderer contract from the Android implementation. PDF session replacement and cleanup can be checked without an Android channel.
- Added a Linux AOT smoke check for default native loading, background workers, all four document edits, saving and reopening from disk. This runs outside the source working directory.
- Added no runtime dependencies or network services. Existing engine pins remain at the latest reviewed stable releases.

## Known Limitations

- Android remains the only packaged app target. Desktop/iOS runners, file dialogs, clipboard integration and PDF rendering still require platform work and validation.
- Windows/macOS library paths and an iOS linked-process strategy are prepared; they are not verified platform builds.
- This release changes platform boundaries and verification rather than adding new document editing commands.
- Native engines remain compiled into the application; no executable code is downloaded at runtime.
- Android runtime checks use an x86_64 emulator. The downloadable APK is ARM64; physical Vivo testing remains separate.
