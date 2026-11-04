# Sheet overview, edge headings and gestures — 0.20.0

Coordinate headings now follow the physical edges of the sheet. They do not
follow the viewport after leaving those edges. View offers explicit heading
pinning; document freeze panes are a separate, still unsupported feature.
Compact coordinate labels and large editor-tool targets are retained.

The native view includes used bounds extended by merged ranges. Fit entire
sheet and Fit width use sparse imported geometry and hidden dimensions. The
whole-sheet overview centers the used range, and fit survives viewport resizing.
Normal touch gestures return to manual scale. Tap-to-edit resolves a document
coordinate, restores readable scale and uses the checked native edit pipeline.
Go to cell also leaves overview mode instead of remaining clamped to used bounds.

The regular FFI view keeps its 128-row/32-column/4096-cell limits. An explicit
rectangle-only overview request iterates stored sparse records, rather than
allocating a rectangle, and returns at most 8192 records. Large sheets are sampled
across the range, including the last record; the response flags simplification.
Per-record display text is limited to 512 Unicode characters and raw input is
omitted, while independent selected-cell input remains exact. Overview cache
coverage cannot satisfy a normal edit-window query. A CustomPainter draws sparse
cells/merges without materializing a large grid of Flutter widgets. Covered merge
cells cannot overwrite the anchor's fill/text. Empty default geometry does not
force an enormous request at deep zoom-out.

Cell gestures use the initial pointer centroid, independent of the scale
recognizer's touch slop. Kinetic pan is preserved; touch-down stops momentum,
while pinch does not start an accidental fling. The legacy row viewport remains
available for older callers. Tool layout stays in the approved nested slab;
frequent View controls appear before the longer gesture explanation.

## Source versions

WordCraft 0.15.1 (`08afab50b6a1ed19f9af55bb9f74d18f5e17bfa0`) and PDFCraft
0.18.1 (`8bb0528bed785283452263b0290321ccf95859be`) replace the previous pins.
GridCraft 0.16.0 and DeckCraft 0.15.0 remain current at the update check.
Manifest/build-script changes and relevant linked-crate diffs were reviewed.
New desktop proofing/i18n/build hooks remain outside the compiled mobile graph.
The linked Word document crate improves its copied-formatting budget; PDF COS
adds incremental cache accounting and counts parsed object-tree memory. These
are upstream changes, not a measured Vivo performance claim. The original
vendored JBIG2 patch remains in use. 121 resolved Rust package notices are bundled.

## Validation

- Clean Flutter analysis; 110 unit/widget tests passed. Added checks cover whole
  fit and width fit, orientation/viewport changes, default edge headings and
  optional pinning, pinch focal-point preservation, kinetic pan/cancel-on-touch,
  tap-to-edit and a pixel check preventing covered merge cells from erasing the
  anchor fill.
- 27 Rust tests passed against updated engine sources. New overview checks cover
  232 × 11 populated cells beyond the normal window limit, a sparse 20,000-cell
  book spanning the Excel grid with capped output and the last record retained,
  bounded text with exact independent selection, and invalid/ambiguous requests.
- 11 Python updater/license checks passed.
- All nine public real-engine integration scenarios passed together on Android
  16 API 36 x86_64. Existing four-format edits, recovery, language, worker/media,
  distant windows, imported geometry and touch resizing remain covered. The new
  case exercises edge headers, fit controls, pending input, overview selection,
  normal editing, export and reopening actual native XLSX bytes.
- A separate private-workbook scenario passed on that emulator: all sparse input
  records were present in the painted overview after loading, full-fit scale
  matched the viewport/used geometry calculation, width fit and tap-to-edit
  worked, and only the intended test cell changed after Save As. Other cell
  inputs, row/column dimensions, hidden state and merged ranges were checked;
  original bytes were preserved. The integration export dialog is mocked.
  An additional ordinary-app check opened this workbook through real SAF and
  exercised both fit controls. Visual QA used live ADB screenshots after loading;
  the complete table fits vertically. Private source and captures remain local.
- An ordinary x86_64 profile APK built from lib/main.dart passes ZIP integrity,
  native 16-KB alignment, 121-package notice and offline-permission checks. Its
  certificate fingerprint is unchanged. Real Android DocumentsUI checks passed
  for all four MIME filters and XLSX import; held-pointer drags changed a column
  404 -> 543 and a row 210 -> 120 physical pixels; Undo restored 210.

Tagged Actions independently rebuilds ARM64, checks the ordinary package, then
signs/publishes with the established certificate. Per-release build-info.json
and signature.txt record the actual artifact/source identity. Actions does not
run Android emulator tests.

## Remaining limits

A private supplied workbook is used only in local QA. Its content, name, hash,
embedded fixture and screenshots are excluded from Git and release inputs.
Public tests use synthetic data. Physical Vivo and a device using actual 16-KB
memory pages are unavailable. Complex Office layout, font substitution, charts,
images, conditional/table styles, freeze panes and auto-fit remain incomplete.
Rust still parses the workbook per request; persistent parsed sessions remain
future work. This release focuses on spreadsheets; new desktop editor tools are
not automatically exposed by updating all four engine sources.
