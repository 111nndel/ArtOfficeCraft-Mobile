# ArtOfficeCraft Mobile

An independent, experimental offline Android office app using Flutter/Dart and native Rust engines.

**Status: alpha 0.7.1 — not a finished office suite.**

| Format | Current capability |
| --- | --- |
| DOCX / WordCraft | Rust FFI: create, parse text, append paragraph and save a new copy. No complete layout or formatting editing. |
| XLSX / GridCraft | Rust FFI: create/read XLSX, edit cells and formulas, recalculate, save a new copy. Limited preview; no full charts/styles. |
| PPTX / DeckCraft | Create/import PPTX, add/delete slides, add/edit text, Save As. Approximate position/shape geometry with direct RGB fills/strokes; no full media/theme/chart rendering. |
| PDF / PDFCraft + Android | Real Android page rendering, thumbnails and zoom; Rust COS/model basic page organization and Save As. Complex editing/forms/signing not complete. |

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

### Offline permission policy

No Android INTERNET or Wi-Fi access permission is requested by this app.
Even Flutter debug and profile manifests deliberately remove the default
INTERNET permission added for VM-service debugging and hot reload.
Consequently Flutter network debugging/hot reload may be unavailable.
Verified APKs must pass an aapt dump permissions check before release.
Android PdfRenderer uses a temporary app-private copy of the document
and removes it after the page has been rendered.

### PDF session lifecycle (0.7.0)

The Android platform renderer opens one PDF in an app-private temporary file
and reuses that PdfRenderer for successive page and thumbnail requests.
Flutter passes only a session token/page/width after opening; the worker
serializes rendering and closes/deletes the document on replace or dispose.
Network and Wi-Fi permissions remain absent from the APKs.

DeckCraft's simplified slide preview now paints rectangles and oval-like
shapes with explicit RGB fills and outlines. This does not render a PPTX
with full PowerPoint fidelity: theme inheritance, embedded images,
animations, effects and complex groups are still unsupported.

0.7.0 has been compiled for ARM64 and x86_64. Full GUI validation on a
running emulator or physical ARM64 hardware is still pending.

### Android file picker compatibility (0.7.1)

The Android system file picker may supply a private temporary path without
the original extension. The previous XLSX, PPTX and PDF screens erroneously
rejected those paths before their document parsers could inspect file bytes.
The editor now validates file contents through its corresponding Rust engine
rather than the cache filename, with a neutral Save As filename fallback
for DOCX, XLSX, PPTX and PDF. Originals are still not overwritten.
The end-to-end open/edit/save workflow for 0.7.1 is pending Android UI
verification; Flutter regression tests pass.

### Limitations and safe handling

The WordCraft mobile UI is currently only a text preview of the document body. Existing rich text, images, tables and page layout are not rendered faithfully. Round-trip behavior for complex DOCX has not been established. Keep originals and save edited files as new copies.

XLSX now uses native GridCraft for actual file operations, but has a limited 55-row, 12-column preview. PPTX uses real DeckCraft operations with limited preview; PDF now displays real page contents with Android PdfRenderer, but advanced PDF editing is unfinished. No format is yet fully featured.

Never publish personal documents in issues, secret keys, signing files, source caches, third-party branding or third-party installers. Read NATIVE_INTEGRATION_STATUS.md for the exact integration status.

Contributions are welcome subject to license notices and safe source review.
