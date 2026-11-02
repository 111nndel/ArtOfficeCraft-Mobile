# ArtOfficeCraft Mobile

An independent, experimental offline Android office app using Flutter/Dart and native Rust engines.

**Status: alpha 0.4.0 — not a finished office suite.**

| Format | Current capability |
| --- | --- |
| DOCX / WordCraft | Rust FFI: create, parse text, append paragraph and save a new copy. No complete layout or formatting editing. |
| XLSX / GridCraft | Rust FFI: create/read XLSX, edit cells and formulas, recalculate, save a new copy. Limited preview; no full charts/styles. |
| PPTX / DeckCraft | Rust FFI: create/import PPTX, add/delete slides, add/edit text shapes and Save As. Simplified preview; no full visuals. |
| PDF / PDFCraft | Demonstration UI; engine not yet integrated. |

### Independence and license

This project is **not affiliated with, sponsored, certified or endorsed by Microsoft, the ArtCraft Team, or the original Rust authors**. Their names are used to identify dependencies and file formats only. No proprietary installers, logos or screenshots from third-party products are distributed.

Original Rust engine sources are fetched from their own public GitHub repositories and pinned to exact Git commits in upstream/engines.lock.json. Their notices and MIT/Apache-2.0 license texts are preserved in licenses/upstream/. Read THIRD_PARTY_NOTICES.md and LICENSE.

### Build locally

Prerequisites: Flutter SDK, Android SDK with NDK, Rust, Python 3, Git.
Official download instructions: https://docs.flutter.dev/get-started/install , https://rustup.rs/ and https://developer.android.com/studio .

Install Rust Android ARM64 target:

    rustup target add aarch64-linux-android

Then from a PowerShell prompt in this repository:

    .\stage-rust-engines.ps1
    flutter pub get
    flutter analyze
    flutter test
    .\native\build_android_arm64.ps1
    flutter build apk --debug --target-platform android-arm64

The native build verifies locked source commits and refuses modified upstream checkouts. ANDROID_HOME should point to Android SDK; ANDROID_NDK_HOME is optional if Android NDK is installed under SDK/ndk.

For one-command Windows debug build: run build_native_preview.ps1. Debug APK is a development preview, not for production release. Release signing is deliberately not configured.

### Upstream updates

- check-rust-engines.ps1 — check whether newer upstream tags exist.
- stage-rust-engines.ps1 -Latest — download new stable source revisions into ignored staging folders.
- Update the pinned commit only after reviewing licenses and API compatibility, building and testing all document formats.

Automated GitHub Actions checks are not yet enabled in this public repository. Local scripts can check and stage upstream releases without publishing executable binaries.

### Limitations and safe handling

The WordCraft mobile UI is currently only a text preview of the document body. Existing rich text, images, tables and page layout are not rendered faithfully. Round-trip behavior for complex DOCX has not been established. Keep originals and save edited files as new copies.

XLSX now uses native GridCraft for actual file operations, but has a limited 55-row, 12-column preview. PPTX uses real DeckCraft operations with limited preview; PDF is still a demonstration. No format is yet fully featured.

Never publish personal documents in issues, secret keys, signing files, source caches, third-party branding or third-party installers. Read NATIVE_INTEGRATION_STATUS.md for the exact integration status.

Contributions are welcome subject to license notices and safe source review.
