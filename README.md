# ArtOfficeCraft Mobile

An independent, experimental offline Android office app using Flutter/Dart and native Rust engines.

**Latest validated release: alpha 0.15.0 — not a finished office suite.**

[Download Android previews](https://github.com/111nndel/ArtOfficeCraft-Mobile/releases)
· [Contribute or fork this app](CONTRIBUTING.md)

English and Russian UI follow the Android language, with a persisted override in
About. Spreadsheets support pinch zoom and pan; PDF opens at page width in the
full available canvas, with optional thumbnails and fit controls. Large editor
tool targets and the approved nested slab navigation remain unchanged.
See [0.15.0 validation and limits](docs/validation-0.15.0.md).

| Format | Current capability |
| --- | --- |
| DOCX / WordCraft | Create/read DOCX, edit plain paragraphs directly on the page with cursor/selection, selected bold/italic/underline/font size and paragraph alignment/spacing; undo/redo; save a new copy. No complete paginated layout. Inline objects/revisions/protected paragraphs are read-only. |
| XLSX / GridCraft | Create/read XLSX, edit cells/formulas with guarded Save As and undo/redo; persisted font/fill/borders/alignment/wrap/number formats. Lazy rows; bounded preview (55 × 12, up to 1600 populated cells inspected per sheet); no complete Excel rendering. |
| PPTX / DeckCraft | Create/import PPTX, add/delete slides, add/edit text, Save As. Approximate position/shape geometry with direct RGB fills/strokes; embedded PNG/JPEG/WebP and graphical thumbnails; no full theme/chart/animation rendering. |
| PDF / PDFCraft + Android | Real Android page rendering, thumbnails and zoom; Rust COS/model basic page organization and Save As. Complex editing/forms/signing not complete. |

### Architecture and current limits

Flutter owns touch interaction and display. `DocumentBackend` sends file parsing,
editing, recalculation and serialization to Dart worker isolates, where the
bounded C ABI invokes the four pinned Rust adapters. Native buffers are released
on success and on error. Each edit still serializes and reparses a whole document;
a persistent native document/session model and faithful page layout are future work.
DOCX keeps the active paragraph draft locally while typing; moving to another
paragraph, Done, formatting and Save As flush it through the native adapter.
Failed commits keep the visible draft and block export of stale bytes.
Grid similarly flushes pending input before Save As or changing cells/sheets,
and preserves styles on value/formula replacement. Applied Grid edits update
the app-private working copy. Locally written recovery checkpoints retain pending
Word/Grid/Deck input and modified PDF bytes after process termination; Home offers
to resume them. Only the last completed checkpoint is recoverable, and undo history
is session-local. See docs/validation-0.15.0.md for current checks and limits.
The shared panel navigation follows design/INTERACTION_SPEC.md.

The mobile app integrates four independent upstream projects. It is an independent
Android port, rather than a GitHub fork with a single upstream parent:

| Engine | Original source | Pinned version |
| --- | --- | --- |
| WordCraft | https://github.com/storytold/wordcraft | v0.14.0 |
| GridCraft | https://github.com/storytold/gridcraft | v0.15.0 |
| DeckCraft | https://github.com/storytold/deckcraft | v0.14.1 |
| PDFCraft | https://github.com/storytold/pdfcraft | v0.17.0 |

Exact commits are recorded in `upstream/engines.lock.json` and embedded in the
native binary (`ac_engine_info`). The About screen reads those binary values.
Rust dependency license texts are included in the APK and in its Licenses screen.
Updates require reviewed source changes, compatible adapters, tests and a new APK;
there is no runtime download or replacement of native engines.

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
    python tools/collect_rust_licenses.py
    .\native\build_android_arm64.ps1 -Release
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
and removes it when its session closes or is replaced.

### Earlier release validation and history

The version-specific results below describe earlier builds. They are not a
claim of complete compatibility or of testing on Vivo hardware.

### PDF session lifecycle (0.7.0)

The Android platform renderer opens one PDF in an app-private temporary file
and reuses that PdfRenderer for successive page and thumbnail requests.
Flutter passes only a session token/page/width after opening; the worker
serializes rendering and closes/deletes the document on replace or dispose.
Network and Wi-Fi permissions remain absent from the APKs.

DeckCraft's simplified slide preview now paints rectangles and oval-like
shapes with explicit RGB fills and outlines. This does not render a PPTX
with full PowerPoint fidelity: theme inheritance, external-linked images,
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

### PPTX text dialog lifecycle and tested Save As (0.7.2)

An Android GUI test revealed a Flutter framework assertion caused by
prematurely disposing the edit dialog's TextEditingController.
The dialog uses a self-owned TextFormField now, with two widget regression
tests for applying and cancelling changes.

In a dedicated Android 15 x86_64 QA emulator, the real application:
opened an existing 2-slide PPTX through Android SAF; displayed slide 2;
edited a text shape; saved a new PPTX copy via Android Save As.
The copied PPTX was pulled back and its ZIP integrity and actual edited
slide XML were verified. The original file was not overwritten.

PDF opening and page display were also confirmed on this emulator with a
real text PDF. These targeted GUI checks do not establish full document
round-trip fidelity, exact PowerPoint rendering, complex PDF editing, or
behavior on a physical ARM64 phone.

### Embedded PPTX graphics (0.8.0)

DeckCraft can now read embedded PNG/JPEG/WebP from actual PPTX slides
via a slide-authorized, offline, bounded Rust FFI call. Flutter paints
pictures in approximate slide positions and renders real slide
thumbnails. Image extraction runs in background isolates. A generated
original colored PNG was visible in the Android 15 emulator, and
Windows Dart FFI tests established byte-identical preservation after
a DeckCraft text edit, despite media ID renumbering on export.

Create a test picture PPTX with the standard-library-only script
tools/make_pptx_image_fixture.py (input two-slide PPTX, output PPTX).
Then test with tools/smoke_deck_images_ffi.dart and the Windows Rust DLL.
Neither external media links nor hidden online requests are used.
Full crop, effects, themes, grouping and animation fidelity remain
future work. A physical ARM64 phone has not been tested.

### Small-screen usability (0.8.1)

The four document cards now open editors under a truthful heading,
without duplicate navigation or outdated no-real-file claims. For
narrow (under 330 dp usable width) phones, the grid becomes a single
column to avoid text overflow. The PDF page actions are labelled and
use 48 dp minimum-height buttons in a horizontally scrollable strip.
Tests cover small-width layouts, disabled operations and scrolling.

The agreed original HTML mockup remains in design/ as documentation,
explicitly excluded from GitHub Linguist language percentages via
.gitattributes. This does not change the actual language mix of the
running Flutter/Rust Android application. See MOBILE_USABILITY.md for
mobile interaction guidelines and outstanding real-device UX checks.

### Editor action ergonomics (0.8.2)

Native DOCX, XLSX and PPTX screen controls have been adjusted for
one-handed use on smaller devices. DOCX Append paragraph / Save copy
buttons are vertically stacked below 440 dp, XLSX table cells and
headers now measure 48 dp in height, and XLSX/PPTX action labels are
visible in a horizontally scrollable 48 dp touch toolbar. The XLSX
New workbook action is explicitly labelled so it is not mistaken
for adding a sheet. The formula input hint fits narrow screens.

The QA Android 15 emulator at 320 dp equivalent successfully showed
DOCX and XLSX editor layouts using newly created documents. The QA
emulator then exited during a keyboard test, so PPTX toolbar
verification and the keyboard flow remain pending. See
MOBILE_USABILITY.md for unfinished validation. This release does not
claim new file-format capabilities, full layout fidelity, or a
physical ARM64 hardware test.

### Large-text accessibility and editor help (0.8.3)

The home editor cards now handle 320 dp layouts at Flutter text scale
160% and 200% without widget overflow. For a larger accessibility
font, the landing banner becomes compact so document choices remain
reachable. The DOCX text field now releases keyboard focus after
successfully adding a paragraph, revealing its result.

Long format limitations in DOCX, XLSX, PPTX and PDF are still
clearly available, but now open in a bounded scrollable bottom sheet
instead of permanently occupying the editing canvas. This avoids
the 24 px vertical overflow discovered on Android when expanding
a long PPTX warning at 150% system font scale. The final bottom
sheet was tested on the Android 15 QA emulator for scrolling and
closing; no Flutter error was observed.

Four widget tests verify the 160%/200% Home layout and both outcomes
of the unsaved changes dialog. Another widget test checks the
format-limits sheet at 200%. Native engine behavior is unchanged.
Full accessibility auditing and testing on physical ARM64 hardware
are outstanding.

### Limitations and safe handling

The WordCraft mobile UI is currently only a text preview of the document body. Existing rich text, images, tables and page layout are not rendered faithfully. Round-trip behavior for complex DOCX has not been established. Keep originals and save edited files as new copies.

XLSX now uses native GridCraft for actual file operations, but has a limited 55-row, 12-column preview. PPTX uses real DeckCraft operations with limited preview; PDF now displays real page contents with Android PdfRenderer, but advanced PDF editing is unfinished. No format is yet fully featured.

Never publish personal documents in issues, secret keys, signing files, source caches, third-party branding or third-party installers. Read NATIVE_INTEGRATION_STATUS.md for the exact integration status.

Contributions are welcome subject to license notices and safe source review.


### Approved mobile workspace design (0.9.0)

The Flutter home screen now follows `design/ArtOfficeCraft_Mobile.html`:
light workspace, four format colors, search, recent files, favorites,
format filters, templates, and bottom navigation. This HTML is a design
reference, never the running editor. The unused in-memory demo editor
has been removed; every document card opens the existing native screen.

Primary controls use 52 dp touch targets with 14–18 sp labels. Cards
switch between one, two and four columns; large system text causes
reflow rather than forced font shrinking. Spreadsheet cells are now
56 dp high with 16 sp values. All four native headers share a readable
filename and status. Native file editing capabilities remain limited
as described above; this is not the complete HTML feature catalog.

Successfully opened files and successful Save As results receive an
app-private local copy. The file list, search and favorites use this
persistent index and reopen the private copy through the native engine.
Unsaved edits are **not** silently autosaved; the existing exit guard
and explicit Save As workflow remain. Clearing app data/uninstalling
removes private copies. Export important files through Save copy.
The storage channel requests no broad storage or network permissions.

Plan document, team budget and idea presentation starters are created
through WordCraft, GridCraft and DeckCraft. Their content is basic and
not an exact reproduction of the HTML formatting.

Validation: Flutter analyze reports no issues; all 33 Flutter tests pass.
New checks cover 320/360/393 dp at 100%/200% text, editor navigation,
search/favorites, storage restart, concurrent imports and corrupt-index
handling. ARM64 and x86_64 debug APKs compile with the existing pinned
native libraries; aapt confirms no INTERNET/Wi-Fi permission in ARM64.
This iteration has not completed a physical Android phone / TalkBack /
keyboard-and-SAF end-to-end test. Full Office fidelity remains unverified.
