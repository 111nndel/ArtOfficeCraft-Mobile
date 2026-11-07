# Compact spreadsheets and reviewed engine updates — 0.19.0

## Connected behaviour

Grid column headings now use a 28 logical-pixel bar (previously 56); row headings
use 46 pixels (previously 64), with fixed 11-pixel labels. Coordinate labels use
no system text scaling and remain outside the document transform. Tool buttons
keep their 52-pixel targets; the approved single nested slab is preserved.
Document font sizes remain independent of system UI scaling, with pinch zoom.

Imported shrink-to-fit is now honoured for unwrapped text using a scale-down-only
fit. It is editable inside Cell format and persists via native XLSX style data.
Wrapping takes priority. This does not auto-fit row heights or column widths.

Formula tools connect to actual GridCraft workbook mutations. AutoSum requires
an empty, unmerged cell; it scans a contiguous numeric/cached numeric-formula
range above first, then left. It inserts SUM, recalculates, preserves destination
style and passes through the existing checked preview/history/save pipeline.
No adjacent range, occupied targets, malformed actions and protected workbooks
fail without changing original input bytes. Recalculate refreshes supported
formula caches; it does not add support for every Excel function.

## Source update

Exact upstream tags/commits are in `upstream/engines.lock.json`: WordCraft 0.15.0,
GridCraft 0.16.0, DeckCraft 0.15.0, PDFCraft 0.18.0. Manifest and build-script
changes were reviewed before staging/pinning. GridCraft adds its math and RaTeX
dependencies. PDFCraft's vendored hayro-jbig2 0.3.0 contains required bounded
JBIG2 decoding API absent from the registry replacement. The native root now
preserves this original source patch. The sync tool verifies commit/clean source,
contained patch path and package identity, with an idempotent managed block.
It refuses changed patch kinds or unrelated root patches for explicit review.
Cargo.lock remains checked in; ordinary builds use --locked.

License collection includes 121 resolved Android Rust packages. Five RaTeX
0.1.14 registry packages lack their standalone license texts. Supplemental source
notices are tied to exact repository/VCS commit, version, license expression and
text hashes. Collection is offline and still fails on unknown missing licenses.
Original notices and SIL OFL font attribution are preserved verbatim.

## Validation

- Flutter analysis: no issues; 107 unit/widget tests passed, including coordinate
  heading sizes at 3× system text scale and 500% sheet zoom; formula-tool dispatch,
  dirty input preservation and undo interaction.
- 24 Rust tests passed against the updated sources. Added vertical/horizontal
  AutoSum with saved/reopened formula/value/style, nonempty/no-range/protection
  rejections, and a stale imported formula cache (999 -> 20) retaining column size
  and leaving original bytes unchanged.
- 11 Python tests passed, including managed source patch validation and exact
  supplemental license provenance/content checks.

- Eight real-engine integration scenarios passed on Android 16 API 36 x86_64.
  Existing four-format edits, recovery, language, workers, media, distant windows,
  geometry and finger resize checks pass against updated sources. The new
  scenario exercises actual AutoSum/recalculate buttons, undo/redo, Save As
  output and reopening the saved SUM result 20, plus imported shrink-to-fit.
  Export in this integration case uses a mocked platform dialog.

The tagged Actions workflow independently rebuilds ARM64 from these pinned
sources and runs offline permission, ELF/ZIP 16-KB alignment and signature checks
before publishing. Per-release build-info.json and signature.txt record the
actual artifact and source identity. Actions does not run emulator scenarios.

## Limits

The user's original XLSX and physical Vivo Android 16 were unavailable. These
checks do not establish full visual round-trip fidelity for that file. Conditional
and table styles, charts, images, frozen panes, auto-fit, rotation and other
features remain incomplete. Font substitution can change layout. Rust still
re-parses the workbook for each window/edit; persistent parsed sessions remain
future work. All four engine updates compile selected crates used by the mobile
adapters; this does not expose every desktop editor command automatically.
Future upstream updates remain stage/review/pin/build operations, not binary
hot updates or an enabled scheduled updater on the unchanged default branch.
