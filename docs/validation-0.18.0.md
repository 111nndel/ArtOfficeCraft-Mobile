# Imported sheet geometry and touch resizing — 0.18.0

## Behaviour

Home and all four editor open commands now share a typed picker configuration:
DOCX, XLSX, PPTX or PDF MIME plus extension (and iOS UTI). Unsupported legacy
DOC/XLS/PPT formats are not advertised. Android still owns the provider browser;
provider-specific presentation of disabled files/folders is outside the app.
Cancellation leaves the current screen/document intact.

The XLSX window response now includes sparse, coalesced geometry runs in document
pixels, merged ranges and the gridline setting. Binary prefix/index lookups skip
hidden blocks without walking a million rows. The viewport mounts intersecting
cells in both axes; a merge is one widget, including when its anchor is outside
the visible window. Native queries additionally include intersecting merge
anchors. Selection/edits inside merges resolve to the anchor. Optional sorted
visible-row/column index lists cross hidden gaps without increasing the existing
128 × 32 / 4,096-cell query bound. Older rectangle requests and ABI 1 remain valid.

Cell presentation includes vertical alignment, unlimited wrapped lines within the
imported height, font face/size/strike and the existing colours/fills/borders/number
formats. Document text uses document font sizes independently of UI text scaling;
zoom provides the mobile enlargement. Original fixed layout is the fallback only
for older/fake backends without geometry metadata.

Hold a column heading and drag horizontally, or a row number and drag vertically.
The preview follows finger movement in document pixels at the current zoom.
On release, a validated native rowHeight/columnWidth operation changes real XLSX
geometry. Pending cell input is committed first. Bytes and checked preview must
succeed before history advances. Cancel/failure restores the committed view.
Headers render outside the document transform: their touch width, bar height and
font size stay fixed even at 500%, without shifting the pinch focal point.
Header element identity remains stable while visible cell counts change, so a
drag is not cancelled by virtualization. Pan/pinch remain available; zoom extends
to 500%. Instructions stay inside View in the approved slab.

## Completed validation

- Clean Flutter analysis; 105 unit/widget tests passed. New cases cover sparse
  geometry/hidden blocks, merge hit targets/partial visibility, both actual
  pointer-driven resize gestures with layout updates, subsequent pinch/pan and fixed heading bounds at maximum zoom,
  and actual platform-channel requests from Home and every editor.
- 21 Rust tests passed, including an independently constructed OOXML fixture
  (tools/make_grid_layout_fixture.py, not our Rust writer). Import/reopen checks
  dimensions, merged title, colours, vertical alignment, hidden lines, formula
  retention and resized output. Sparse native queries cross the full address
  range with four lookups; malformed index lists/bounds are rejected.
- Five Python updater/SDK retry tests passed on Linux.
- Seven real-engine integration scenarios passed on Android 16 API 36 x86_64.
  The new scenario imports the independent fixture, verifies merged geometry and
  hidden headings, commits pending title text through a finger resize, changes
  width/height, undoes/redoes, and inspects exported XLSX bytes for retained
  geometry/merge/percentage formatting. The original bytes remain unchanged.
  The platform export dialog is mocked in this integration scenario.
- Existing Word/Grid/Deck/PDF edits, recovery, language/zoom, ordered worker and
  exact embedded picture scenarios remain passing. The AA1000 case also checks
  the selected value while other windows are loaded.
- An ordinary offline x86_64 profile APK was rebuilt after test manifests were
  restored and passed the package/permission/signature/ELF/ZIP alignment checker.
- The ordinary app also passed tools/test_grid_touch_import.js on Android 16.
  All four real ACTION_OPEN_DOCUMENT requests had their exact MIME types. The
  independent fixture opened through the real system picker. Actual touchscreen
  DOWN/hold/MOVE/UP events resized the column from 404 to 543 screen pixels and
  the row from 210 to 121; Undo restored the 210-pixel row and Redo reapplied it.
  These are emulator display measurements, not the file's document-pixel units.
  The merged title, colours, borders, date/percentage values and hidden row were
  visually inspected. The dedicated helper handles restored provider drawers and
  browses storage directly because ADB-pushed fixtures are not DownloadManager
  entries. No extra application permissions were needed. The ordinary APK retains
  the original signing fingerprint and has no INTERNET permission.

## Limits

This is an incremental XLSX layout renderer, not full Excel fidelity. Conditional
formatting, table style expansion, exact custom font substitution, images/charts,
freeze panes, print layout, auto-fit and many range commands are not connected.
Some border types, text rotation and rich text remain approximate. Tiny imported
cells require pinch zoom for precise touch targeting; tool buttons remain large.

Window reads still parse a complete file; sparse geometry/merge metadata is sent
with each view. A retained native workbook session and large-file cancellation
remain future work. Original cached formula values may be stale until recalculated
by an edit. Physical Vivo and actual 16-KiB-page runtime tests were not performed.
The four upstream pins/dependencies are unchanged; only our adapter is 0.18.0.
