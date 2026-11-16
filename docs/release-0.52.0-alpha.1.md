# ArtOfficeCraft Mobile 0.52.0-alpha.1

## What's New

- About and the licence page show the application version embedded by Flutter
  at build time instead of the outdated hardcoded 0.40.0 label. The project
  description now reflects the Flutter/Rust editors and their current features.
- App updates offer Manual and Automatic modes. Manual is the default: startup
  makes no update request. Automatic checks and downloads from this repository's
  GitHub Releases on launch/resume, at most once daily.
- Downloads run asynchronously with progress, cancellation, bounded sizes,
  HTTPS host restrictions and temporary-file cleanup. A verified cached update
  remains installable after a restart without downloading it again.
- Before installation Android checks the SHA-256, package ID, increasing package
  version, device ABI and the certificate of the installed application. Android
  handles source permission and installation confirmation; updates do not
  interrupt an editor or silently replace the app.
- New INTERNET and REQUEST_INSTALL_PACKAGES permissions support this opt-in
  updater. Editing, rendering and OCR still run locally. No document uploads,
  Wi-Fi controls, broad storage permission or new package dependencies.
- Four engine pins and Rust core 0.51.0 / ABI 1 are unchanged.

## Known Limitations

- Automatic mode works while opening/resuming the app; it is not an always-on
  background service. Android still requires the user's installation decision.
- Published update APKs currently target Android ARM64. The updater needs access
  to GitHub; offline/rate-limited checks can be retried manually.
- Preview release signed with the existing development certificate.
