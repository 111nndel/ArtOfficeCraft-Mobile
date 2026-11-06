# ArtOfficeCraft Mobile — Rust/Flutter integration checkpoint

Current checkpoint: app 0.33.0 / core 0.32.0, native ABI 1. The approved mobile
panel design is implemented across all editors. DOCX supports in-page paragraph
editing and selected formatting. XLSX additionally supports guarded pending input,
undo/redo, native cell styles and number formats. Deck text forms stay within the
slab; PDF uses Android rendering with explicit session cleanup. See
`docs/release-0.33.0-alpha.1.md` and `design/INTERACTION_SPEC.md` for the current state.
English/Russian UI, sheet pinch/pan and full-width PDF viewing are connected.
Native backends now own persistent Dart workers with ordered processing, checked
edit/view snapshots and explicit shutdown. Word history restoration is guarded;
undo/redo share a bounded memory budget. Persistent parsed Rust models remain future work.
XLSX now exposes additive `ac_xlsx_inspect_window` for bounded rectangle/selection
queries, independent of the legacy global preview cutoff. The mobile view mounts
only visible rows and columns, with full Excel coordinate bounds and Go to cell.
App appearance is durably saved and preloaded before startup paint.
XLSX imports sparse dimensions, hidden lines, merges and vertical alignment.
Long-press/drag on headings previews and persists row/column sizes with undo/redo.
The selected value remains independent of the loaded window. Picker MIME/extension
filters are shared by Home and all editor open commands.
0.19.0 reduces heading labels to 11 logical pixels and the column bar to 28;
row labels remain 46 wide, independent of document zoom and system text scale.
AutoSum/recalculate use real native workbook operations, checked snapshots and
existing undo/redo. Imported shrink-to-fit is displayed and can be changed in
Cell format. Original PDFCraft vendored JBIG2 fixes are preserved by a managed
root Cargo patch, resolved from the exact reviewed upstream source.

0.21.0 removes the 0.20 thumbnail overview and automatic centering. The sheet
stays editable at 10–500%, including surrounding empty cells. Reduced zoom paints
only the viewport, with the same exact native window data and hit-testing; tapping
does not change zoom. Exact queries allow up to 262,144 visible intersections
(8,192 rows / 2,048 columns per axis), with no sampling or text truncation.
Coordinate headings still follow physical sheet edges by default; optional pinning
stays in View. Inertial pan, focal-point pinch and touch resizing are preserved.
Successful imports and new documents reset the workspace identity in all four
editors, preventing a new import from overwriting the previous recent copy.

0.23.0 connects rectangular touch selection with 44-dp handles and edge scrolling.
Range formatting/clear use the pinned native workbook and preserve clear-time
styles; recalculation, checked snapshots and history still apply. Range actions
are limited to 4096 cells and complete merges. Word exposes selected RGB/automatic
color and left-indent presets; preview and inline/static display share foreground
color and multiple line spacing. Four upstream pins and dependencies are unchanged.

0.24.0 adds the pinned gridcraft-engine command facade for copy/paste. The C ABI
adds bounded copy-range metadata and a three-buffer rich paste operation; the
Dart worker returns checked XLSX/view snapshots before publishing edits. Only
selected TSV and an opaque identity token enter Android's clipboard. One source
snapshot stays in memory (24 MiB maximum); pasted selections are limited to 4096
cells and text to 256 KiB UTF-8. All/values/formulas/formats modes use upstream
commands and rebasing/style interning. Partial merges, protected destinations,
array/spill ranges and format-only merged sources are guarded. Upstream source
pins remain unchanged; nine transitive packages are newly resolved and their
notices are bundled. Word/Deck/PDF have no new feature in this release.

0.25.0 connects the four pinned GridCraft whole-row and whole-column operations
through the existing edit ABI. The selection supplies a contiguous span, and
native serialization preserves the shifted model and rewritten supported formula
references. The worker checks the resulting view before the editor records one
undo step. Deletion lists the exact lines in the same nested panel. The app
bounds each operation to 256 lines and keeps both snapshots within the existing
24 MiB history budget. No dependency or upstream pin changes are required.

0.26.0 adds touch page turns and a virtualized continuous reader to PDF and PPTX.
Single-page swipes turn at the visible page edge. The continuous canvas mounts
visible pages and tracks the active page for the editor tools and thumbnails.
Reading preferences are stored per format in Android's private settings.
DOCX currently provides an editable continuous paragraph view.

0.27.0 connects GridCraft range sorting through the existing edit ABI.
The Data panel accepts a sort column, direction and an optional header row.
The Dart worker validates the new XLSX view before committing an undo step.
All four original engine source pins and their bundled notices are updated.

0.28.0 exposes worksheet AutoFilter value lists and apply/remove commands.
The background worker reads options, writes the real XLSX filter and verifies
the view before the editor commits an undo step. Rows hidden by a filter keep
their cells and styles. The four engine pins match their latest stable tags.

0.29.0 adds searchable PDF bookmarks and direct page/slide number navigation.
PDFCraft's pinned organize crate resolves local destinations on the worker.
The viewer uses the resolved page numbers and titles for navigation.

0.30.0 adds touch positioning and resizing of supported PPTX objects,
standard text annotations in PDF and a lazy Word paragraph viewport.
Search and draft restoration can anchor the Word viewport at a distant block.

0.31.0 connects PDFCraft's page-content editor. The worker loads up to 256
supported text blocks on demand for the current page. It checks the source block
before rewriting its text and passes the saved bytes back to Android for rendering.
Invisible OCR text is excluded.

0.32.0 adds touch-positioned PDF text insertion. The worker embeds the pinned
PDFCraft Inter font, checks that the text fits and adds a page content stream
using the displayed crop and rotation. The saved text remains selectable.

0.33.0 adds PDF scan recognition on the Android renderer's background worker.
The offline recognizer uses Tesseract4Android 4.9.0 and Russian and English
tessdata_fast models. The build pins all input hashes and the app bundles the
models and notices. The result is available in the text panel for selection
and copying. PDFCraft continues to own PDF serialization and editing.

The version-labelled sections below describe historical checkpoints and retain
their original limitations; they are not a current capability inventory.

## Source and provenance

Pinned upstream repositories:
- WordCraft v0.15.2, commit `edfea68101220c9bdc4b2b0ccf4acd9612bedb6e`.
- GridCraft v0.16.1, commit `e581bc95b2a17d2a744a115478a20a1c2ad1ef72`.
- DeckCraft v0.15.1, commit `9bac60ff53029039c82083ee574c22d74c1541f1`.
- PDFCraft v0.18.2, commit `7faa4f35cefb0dea04137ec475bdc770945c22cd`.

All repositories are downloaded and checked against pinned SHAs; original ZIP files untouched.

## Actual Rust functionality currently connected

`native/artoffice_core/src/lib.rs` builds against the **real** `wordcraft-doc` and `wordcraft-docx` crates from the pinned WordCraft repository, with no manual reimplementation of DOCX parsing.

The binary C ABI offers:
- `ac_engine_abi_version`
- `ac_docx_create`: create an OOXML DOCX from a UTF-8 paragraph.
- `ac_docx_inspect`: parse DOCX and return structured JSON with main-story paragraphs and table count.
- `ac_docx_append_paragraph`: parse input DOCX, append a paragraph with WordCraft model, and return output DOCX bytes.
- `ac_result_free`: free Rust-owned buffers from Dart.

Memory/error boundary: input size limits, UTF-8 validation, catch_unwind on exports, result status and explicit buffer destructor. ABI tested from Dart on Windows with a DLL and built for Android arm64.

Flutter screen `lib/native/native_word_screen.dart` uses system Android file dialogs to pick an existing file and to **save a new copy**; it does not silently overwrite originals. It displays a text-only WordCraft preview and supports appending a new paragraph, creating documents, and saving a copy.

**Do not misrepresent this as a complete DOCX editor.** Original formatting, page layout, tables and images are not rendered on the mobile screen. They are read/written by the WordCraft document model where supported, but round-trip fidelity for complex files remains unverified. Existing paragraphs are not yet editable on this screen.

## GridCraft XLSX (0.3.0)

Pinned GridCraft 0.15.0 crates gridcraft-core, gridcraft-model,
gridcraft-xlsx and gridcraft-calc are linked in native Android Rust.
The new FFI exports ac_xlsx_create, ac_xlsx_inspect, ac_xlsx_set_cell.
GridCraft reads and writes actual XLSX bytes; a JSON request updates A1
cell input in a specified sheet and recalculates formulas before saving.

Flutter has a native_grid_screen with open/create/edit/Save As and sheet
switching. Only 55 rows and 12 columns are visible; JSON inspection is
limited to 1600 stored cells per sheet. No chart/style image fidelity has
been established. Protected sheets refuse editing. Originals remain
untouched through the Android save-as dialog.

FFI smoke tested on Windows: A1=12, B1=8, C1=SUM(A1:B1)
then reopened as XLSX; displayed result 20. Physical Android device
testing is still pending.

## DeckCraft PPTX (0.4.0)

DeckCraft 0.14.1 model and pptx crates are linked into the real Rust dynamic
library. FFI ac_pptx_create, ac_pptx_inspect and ac_pptx_edit create and parse
PPTX, add/delete slides, add/change text objects and export changed PPTX bytes.
Flutter native_deck_screen.dart uses native DeckCraft to create/open PPTX,
edit shapes and Save As via Android document picker. Source originals are not
silently overwritten.

Tests: 7 Rust tests passed across all three connected engines, and Windows
Dart FFI smoke test passed for PPTX creation, slide/text insertion, editing
and reopening. Android ARM64 shared library and debug APK 0.4.0 built.
A separate running emulator was occupied by ToTstore, so PPTX 0.4.0 mobile
UI remains untested in Android Emulator. DOCX/XLSX 0.3.0 have previously
passed emulator create/edit/save/reopen workflows.

This is NOT a full presentation renderer. Images, SmartArt, groups, charts,
animations and exact complex PowerPoint formatting are not rendered. Complex
file round-trip compatibility is not yet validated.

## PDFCraft PDF page-organizing integration (0.5.0)

Pinned PDFCraft 0.17.0 COS and model crates are integrated into the
native Rust dynamic library. Exports:
- ac_pdf_create: blank, valid A4 PDF.
- ac_pdf_inspect: page count, dimensions and rotation; NO page rendering.
- ac_pdf_edit: rotate 90 degrees clockwise/counterclockwise,
  insert a blank page, duplicate a simple page, delete a simple page
  (not the last), or move a page one position up/down.
Only a new PDF copy is saved by the Android system file picker.
The operations use the ORIGINAL PDFCraft COS and model APIs, plus our
explicitly limited page-tree editing bridge.

Upstream pdfcraft-organize 0.17.0 could NOT be compiled with pinned
hayro-syntax 0.7.2: pdfcraft-content calls TypedIter.committed(),
which that dependency does not implement (Rust error E0599).
The upstream checkout and Git SHA remain untouched. Consequently
pdfcraft-organize is NOT linked and its advanced safety semantics
are NOT claimed. Our restricted implementation refuses some complex
page edits and does not repair all cross-references, annotations,
forms, structure trees or signatures after rearrangement.

The PDF screen is a page organizer, not a content renderer. Images,
text, stamps, annotations, forms, signing, OCR and page thumbnails
are not implemented. Signed PDFs will lose valid signatures after
editing and full-saving. Preserve the original for recovery.
Tests: nine combined Rust tests passed. Windows Dart FFI smoke test
created a PDF, duplicated and rotated a page, saved and re-read it.
Physical Android / emulator PDF 0.5.0 testing is pending.

## PDF rendering on Android (0.6.0)

The PDF screen now displays actual page contents using the first-party Android
PdfRenderer (API 21+). PDFCraft COS/model Rust continues to edit page
structure and export new copies. The native Kotlin MethodChannel named
artofficecraft/pdf_renderer accepts bounded PDF bytes, a page and width,
renders on a dedicated single background worker, returns PNG, closes all
file descriptors/bitmaps and deletes its app-private temporary PDF file.
Default Flutter debug/profile INTERNET permissions were explicitly removed
from the Android manifests for offline builds. Flutter network debugging/hot
reload may be unavailable. The Android PdfRenderer requires no network or
external-storage permissions.

Flutter displays page PNGs, lazy page thumbnails, and interactive zoom with
explicit errors for encrypted or unsupported PDFs. Rendering is Android
platform PDF rasterization, NOT the separate pdfcraft-render crate.
Requests are capped at 1600 px wide, 2880 px tall, 4.2 million pixels.
Each page currently sends the PDF again; persistent document sessions
are future optimization work.

Confirmed: Flutter analyzer clean; 8 Flutter/widget tests passed (including
three MethodChannel request/validation tests), and Android Kotlin compiled
inside debug APK. Headless Android 15 x86_64 emulator native PdfRenderer
tests passed against a real text PDF (576 sampled nonwhite pixels) and
a 2-page PDF exported by PDFCraft (successful page decoding). ToTstore
was left foreground throughout these native tests.

NOT confirmed: visual interaction with this new 0.6.0 PDF editor UI
inside an Android emulator or on physical ARM64 hardware. Complex forms,
annotations, signing, rich editing and fidelity still need work.

## PDF session reuse and PPTX basic graphics (0.7.0)

Android Kotlin MainActivity offers three on-device MethodChannel actions:
openDocument accepts bounded PDF bytes ONCE and stores an active PdfRenderer
with an app-private, temporary PDF file. renderPage accepts a session token,
page index and render width (without re-transferring document bytes).
closeDocument closes the matching session and deletes the temp file.
All operations run sequentially on a single background executor. Invalidated
session tokens are rejected, and a new document replaces the previous one
only after successful opening. Flutter closes its session when the PDF
screen is disposed. Only one PDF document is open per Activity.

DeckCraft PPTX inspect now includes direct RGB fill and outline data plus
serialized geometry for text/graphics objects. Flutter draws approximate
rectangles, round corners and ellipse-like shapes with positions and RGB
colors. This preview is not pixel-perfect: inherited theme fills, picture
data, gradient and group composition, charts, animations and complex
geometry paths are not rendered. Original PPTX files are not rewritten
by displaying previews.

Validation: 10 Rust engine unit tests passed, including a DeckCraft RGB
shape fill + geometry round-trip. Flutter analyzer clean and 9 widget
tests passed, including session open/render/close contract tests.
Kotlin Android compilation and APK packaging passed for x86_64 and ARM64.
The actual App UI 0.7.0 remains untested on emulator because ToTstore
is using the only available instance. A separate headless Android PdfRenderer
test has previously passed, but does not test the new MethodChannel path.

## Android SAF import extension fix (0.7.1)

A real Android 15 x86_64 emulator test exposed a previously missed bug:
FlutterFileDialog.pickFile returns a private temporary copy path without
the original filename suffix. XLSX, PPTX and PDF editor screens incorrectly
rejected valid file contents by calling endsWith on that temporary path.
The WordCraft screen already used its Rust parser and only supplied a
fallback filename. The other three screens now do the same: bound input size,
pass the actual data to Rust for validation, and derive a neutral Save As
filename when original extension metadata is unavailable. WordCraft now
checks the size BEFORE allocating the entire document byte buffer.
Three explicit filename-helper regression tests have been added.

On a dedicated ArtOfficeCraft-only Android 15 AVD, 0.7.0 did launch and
display the PDF import screen, but rejected a valid 616-byte PDF by its
temporary cache path. 0.7.1 was compiled, installed and launched, and the
file picker displayed the test PDF; its final file-open operation was not
confirmed because the separate emulator process later exited. Thus UI
import remains a remaining end-to-end test, not a claimed pass.

## Android GUI regression and DeckCraft dialog fix (0.7.2)

On a dedicated Android 15 x86_64 ArtOfficeCraft QA emulator, the actual
App 0.7.1 imported and displayed a real text PDF with both page raster
and thumbnail; its new persistent Android PdfRenderer session works for
the tested one-page file. A valid, 2-slide DeckCraft test PPTX also
imported through the Android system picker and the second slide's text
and positions were visible. A spurious initial ZIP error arose when the
wrong file was selected during automated picking, not from the PPTX.

A second actual device UI problem emerged: applying a shape text change
triggered a Flutter framework assertion about a disposed
TextEditingController. The dialog's controller was disposed as soon as
showDialog resolved, before its reverse route animation had fully
unmounted the TextField. 0.7.2 replaces this implementation with a
self-owned TextFormField, and includes two widget regression tests for
the Apply and Cancel flows. 14 Flutter tests and 10 Rust tests passed.

ACTUAL Android 15 QA confirmation for version 0.7.2:
- App launched and test PPTX was imported through Android SAF picker.
- 2 slides and the text boxes on slide 2 were visible.
- Selected the first text box, appended "_FIX", tapped Apply, and
  confirmed "Sprint presentation_FIX" on both slide and thumbnail,
  with no red Flutter assertion screen.
- Saved a new copy through the Android system Save As picker, at
  Downloads/aoc-test-ArtOfficeCraft.pptx (original left unchanged).
- Pulled copy back from the emulator: valid PPTX ZIP with no corrupt
  members; ppt/slides/slide2.xml contains the edited text.
- Android Internet and Wi-Fi permissions absent from both APK builds.

This is a demonstrated small text-edit round-trip, not a test of all
PowerPoint elements. Gradients, images, theme rendering, charts,
group transformations, fonts and full editing remain incomplete.
No physical ARM64 hardware test has been performed.

## Embedded PPTX media preview (0.8.0)

DeckCraft's ac_pptx_inspect reports imageId for embedded PNG/JPEG/WebP
picture shapes and fills. ac_pptx_image uses the existing FFI buffer
contract, validates an image is referenced by the requested slide,
refuses external links and unsupported formats, and bounds images to
8 MiB. No network access or broad storage permission is required.

Flutter loads images on background Dart isolates (not the UI isolate),
retains at most 12 image futures per document, and draws pictures at
approximate slide positions. The same preview canvas is used for
graphical thumbnails. Thumbnail Container clipping was corrected to
use BoxDecoration after an Android assertion was found during QA.

Windows Dart FFI smoke test validated a PNG extracted from a generated
two-slide PPTX, rejection of access from an unrelated slide, and
byte-for-byte image preservation across a DeckCraft text edit. DeckCraft
renumbered the media identifier on export; this was not image loss.
The dedicated Android 15 x86_64 emulator displayed the PNG on slide 2.
Android thumbnail QA passed on the dedicated x86_64 AVD: the second slide showed the original colored PNG in both the main canvas and thumbnail; tapping slides worked with no framework assertion. A physical ARM64 phone remains untested.

Limitations: only direct embedded raster graphics. Cropping, masks,
complex groups, inherited themes, external image links, effects,
charts, animations, and image editing are not fully supported.

## Usability and GitHub language classification (0.8.1)

A compact usability pass changed only Flutter UI, with no Rust engine
or upstream changes. The home screen now says Open editor rather than
Create, removes the redundant workspace list, eliminates the false
claim that genuine files cannot be opened, and uses one column under
330 dp usable width. The PDF page action bar now provides labelled
48 dp high controls in a horizontally scrollable strip, avoiding
wrapping and ambiguous icons. Existing delete confirmation remains.

Tests include a 320 dp Flutter home layout, a 320 dp PDF control bar,
scroll-to-control interaction, and disabled controls while busy.
The approved design/ArtOfficeCraft_Mobile_Editors_v0.2.html is marked
linguist-documentation using .gitattributes; it remains in source
control but should no longer count as an implementation language.
Detailed ongoing criteria are in MOBILE_USABILITY.md.

## Mobile editor ergonomics pass (0.8.2)

The DOCX editor now arranges the Append paragraph / Save copy actions
vertically when available width is under 440 dp; otherwise they share
the footer. Both controls maintain a >=48 dp touch target.

The XLSX table cell/heading height was raised from 30 dp to 48 dp,
and cell text from 11 sp to 13 sp. The footer is horizontally
scrollable and distinguishes "New workbook" from creating a new
worksheet, while the formula input hint has been abbreviated for
narrow phones and an explicit tooltip documents formula syntax.

The PPTX bottom toolbar now uses labelled actions for New slide,
Add text and Save copy, each >=48 dp, with horizontal scrolling.

Android 15 x86_64 QA emulator at a 320 dp-equivalent simulated viewport:
created an XLSX workbook and confirmed the touch-friendly rows and
scrollable footer appear without visible overflow; created a DOCX
and confirmed full-width stacked actions appear. During a subsequent
DOCX keyboard test, the QA emulator exited; no causality to the
application has been established. PPTX controls on that new build
have not yet been inspected in Android UI. Existing Flutter tests
passed; arm64 on real hardware remains untested. No native Rust
engines or upstream vendor sources were changed.

## Accessibility and keyboard QA (0.8.3)

At 320 dp width, Flutter widget tests now cover 160% and 200% text
scaling and verify Home editor cards do not overflow. At high text
scale Home uses a shorter introductory banner and taller single-column
editor cards so the real editor actions are easier to reach.

UnsavedChangesGuard is explicitly tested for both staying in an
editor and confirming an exit without saving a copy.

On the dedicated Android 15 x86_64 ArtOfficeCraft QA emulator with
a 320 dp simulated width and 150% Android system font scale:
- DOCX: entered text with the on-screen keyboard, appended a paragraph,
  and confirmed it appeared in the document.
- The first pass exposed that the keyboard remained visible after
  committing a paragraph, covering the document. The final build
  unfocuses the text field after success and this was confirmed on
  the emulator: keyboard hid and the new paragraph was readable.
- PPTX: the editor's horizontal action strip remained accessible.
  An initially expanded inline warning caused a 24-pixel vertical
  overflow. The format information has since been moved into a
  bounded, scrollable modal bottom sheet, and the Android test
  confirmed opening, scrolling and closing without Flutter errors.
- The shared FormatLimitsNotice also reduces permanent banner space
  in DOCX, XLSX, and PDF. A Flutter test covers the modal at 200%.

The underlying Rust engines and upstream pins are unchanged. Android
network and Wi-Fi permission declarations remain absent. This targeted
test does NOT establish full DOCX/XLSX/PPTX/PDF feature coverage,
pixel-perfect PowerPoint rendering, or physical ARM64 device success.

## Not implemented yet

- Full GridCraft XLSX formatting/rendering and compatibility regression testing.
- Full DeckCraft PPTX visual rendering, editing and fidelity testing.
- Full PDF annotations, forms, editing, complex round trips, OCR and signing.
- Pixel-perfect WordCraft layout renderer and full Word formatting.
- Comprehensive document fidelity tests on complex real files.
- Signature/release packaging, real-device test, performance benchmarks, crash recovery.

All four formats have partial Rust operations; PDF now displays pages via Android platform renderer, while complex editing is still incomplete.

## Upstream updates integration

Run `python tools/sync_native_pins.py` before native compile. It checks pinned repositories, exact Git commits and dirty files, then rewrites WordCraft, GridCraft, DeckCraft and PDFCraft COS/model path dependencies in `native/artoffice_core/Cargo.toml` to match `upstream/engines.lock.json`. If a pin changes, `stage-rust-engines.ps1` must download the approved version first.

`native/build_android_arm64.ps1` now verifies pins, builds the Android library with the NDK ARM64 linker, and copies it to `android/app/src/main/jniLibs/arm64-v8a/libartoffice_core.so`.

`build_native_preview.ps1` performs Rust rebuild, Flutter tests, ARM64 debug APK build and copies a validation APK to Downloads. New upstream source is never executed automatically merely because a GitHub tag appeared.

## Verification commands

```powershell
cargo test --manifest-path native/artoffice_core/Cargo.toml --lib
cargo build --manifest-path native/artoffice_core/Cargo.toml --release
dart run tools/smoke_word_ffi.dart native/artoffice_core/target/release/artoffice_core.dll
dart run tools/smoke_grid_ffi.dart native/artoffice_core/target/release/artoffice_core.dll
dart run tools/smoke_deck_ffi.dart native/artoffice_core/target/release/artoffice_core.dll
dart run tools/smoke_pdf_ffi.dart native/artoffice_core/target/release/artoffice_core.dll
flutter analyze
flutter test
powershell -ExecutionPolicy Bypass -File native/build_android_arm64.ps1
powershell -ExecutionPolicy Bypass -File build_native_preview.ps1
```

Testing with an actual Android phone via ADB remains outstanding.

## Constraints

APK is debug; Android ARM64 target verified by build. It must not be represented as a finished office suite. Full features require significant engineering and tests, not just exposing existing Rust source trees.


0.22.0 connects exact, case-sensitive paragraph find/replace in Word, including
Unicode offsets, unchanged run preservation and one history step per replacement
operation. Table content remains excluded and protected matches refuse edits.
Grid adds validated named sheets through the pinned upstream model, saves the
active tab and restores sheet context through undo/redo. Deck reorders whole
slides without rebuilding their shapes/media; its history and PDF page history
now preserve selected indices and mutate only after a checked restore. Pending
Deck text is committed without silently switching the slide being reordered.
PDF supports direct page-number moves; displayed width/height from Rust are no
longer swapped a second time for rotated pages. New controls use the existing
nested panel and include English strings. Full Office fidelity remains incomplete.
