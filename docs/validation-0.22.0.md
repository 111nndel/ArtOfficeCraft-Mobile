# ArtOfficeCraft Mobile 0.22.0 validation

## Implemented operations

Word's Find and replace pane uses literal, case-sensitive text search in top-level
paragraphs. Find navigation stays in the document and tools pane. Replace one uses
validated UTF-16 offsets and checks that the selected text still matches. Replace
all is one native transaction/history step; unchanged runs survive the edit.
Protected/revision/inline-object matches refuse replacement. Table contents remain
excluded and the pane says so when tables are present. Limits are 10,000 matches,
64 KiB per replacement paragraph, and bounded query/request text.

Grid adds a named worksheet through the pinned model with its name/protection
checks. Existing cells, formulas, geometry and merges remain in the workbook.
Pending cell input is committed first. History records the sheet index with its
bytes, so undoing creation cannot inspect a now-missing tab. The saved XLSX active
sheet is read on opening; ordinary 10–500% zoom and the 0.21 recent-file fix remain.

Deck moves an existing complete slide up/down or to an endpoint. It does not
reconstruct slides from preview text. Pending text commits before structural
commands without changing which selected slide the move targets. Undo/redo now
cover text and slide edits and retain the selected index.

PDF gains page-order controls, direct moves to a page number and undo/redo. New
page bytes must pass inspection and Android render-session opening before the
current document or history changes. Displayed dimensions supplied by Rust already
include rotation; Flutter no longer applies that swap twice.

All four editors share a 24-MiB/10-step undo+redo budget, excluding current bytes.
History is session-local. A failed restore leaves its target available for retry;
new document loads clear history. Existing recovery checkpoints remain independent.
No additional dependencies were introduced. The four engine source pins and the
reviewed vendored PDF patch are unchanged from 0.21.

## Completed automated checks

- Clean Flutter analysis; 124 unit/widget tests passed. New cases check Unicode
  replacement and failure retention at 320 dp/160% text, sheet creation with
  pending input and positional undo/reopen, slide order and failed restore retry,
  pending text on another slide, PDF rotation geometry, Android renderer failure
  without history loss, and direct page movement.
- 30 Rust tests passed. Added round trips check unchanged Word runs and Unicode,
  replacement/protection limits, named-sheet creation with prior formulas/merges,
  active-sheet persistence, invalid names/protection, slide content/geometry,
  page ordering/rotation and invalid target rejection.
- 11 Python updater/license tests passed.
- Android 16 API 36 x86_64: nine existing real-engine scenarios passed, retaining
  worker/media lifecycle, recovery, English UI, touch zoom, distant cell editing,
  imported layout, resizing, formulas and reduced-zoom export coverage.
- Four additional Android scenarios passed: Word replace/save/undo/redo/reopen;
  Grid pending input/new sheet/undo/reopen-active-tab; PPTX move/save/undo with
  byte-identical embedded PNG extraction; PDF rotation aspect, direct move,
  undo/redo and exported page order. Integration Save As uses a mocked dialog.
- An ordinary profile APK built explicitly from lib/main.dart passes package,
  ZIP/native 16-KB alignment, notices and certificate verification. Offline
  permissions are checked again in the independently rebuilt ARM64 candidate.

Ordinary-app DocumentsUI/resize and unique-name sequential-import/force-stop
checks use tools/test_grid_touch_import.js and tools/test_recent_imports.js on a
dedicated emulator. Release metadata records the independently built artifact,
source hash, offline-package checks and original signing identity.

## Remaining limits

The physical Vivo Android 16 and a runtime using actual 16-KB pages were not
available. Full Word page layout/table editing, spreadsheet charts/complex styles,
full PowerPoint rendering and PDF forms/annotations/signing are not complete.
Window reads and edits still reparse whole files; persistent native model sessions
remain future work. Search is exact and case-sensitive, not regular-expression or
case-insensitive search. Complex Office/PDF round-trip fidelity remains limited;
exports continue to use separate copies.
