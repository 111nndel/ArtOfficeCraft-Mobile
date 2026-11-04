# ArtOfficeCraft Mobile 0.24.0 validation

## Implementation

GridCraft's pinned command engine handles the actual paste; the mobile adapter
exposes only copy metadata and the two allowed paste commands. Rich source bytes
remain in one process-local immutable snapshot. Android receives selected text
plus an opaque random identity token; equal external text without this token
cannot reuse old formatting. Source and target are transferred to the persistent
Dart worker and native result buffers are freed on all paths. Only a successfully
inspected result replaces editor bytes and enters undo history. Source files are
not overwritten; Save As remains the export path.

Limits: 4096 cells, 256 KiB UTF-8 text, 24 MiB rich source snapshot. Partial merges,
array/spill ranges, protected targets and formatting-only merged sources are
rejected before execution. Full merges can be pasted with Paste all. Rich copy is
session-local, not a persisted cache. No cut or transpose operation is connected.
The four upstream pins remain unchanged; gridcraft-engine and its required
transitive packages are added to the existing managed pin/notice workflow.

## Local checks

- 39 Rust tests passed, including formula rebasing, style import, paste modes,
  overlap, quoted TSV and atomic rejection cases.
- 135 Flutter tests passed, including clipboard identity, failed writes,
  immutable source, bounded Unicode text and checked-history UI transactions at
  320 dp / 160% text.
- The real Linux native library passed an actual Dart worker / three-buffer FFI
  smoke test: cross-workbook styles, relative formulas and dependent recalculation.

Cloud build and physical-device results are recorded separately; do not infer
Vivo hardware testing from local tests. The Android 16 gate includes 18 real-engine
integration cases and ordinary-app file picker, touch resize and recent-file tests.


## Initial hosted run

Source `5c0607989df50cc6116e53a57eb311ce673b1a68`, run `41928355536`:
all four test/build jobs passed, including 18 Android integration scenarios and
ordinary-app picker/resize/recent-copy checks. The retained QA report says passed;
25 integration PNGs and nine ordinary-app PNGs were retained. Representative
Word/Grid/Deck/PDF and clipboard captures were visually reviewed. Publication did
not run: environment rules correctly rejected the branch before any signing step.
The release request path was corrected to use the allowed tag context, with a
new full gate at that tag. App/native/editor source is unchanged by this CI fix.
