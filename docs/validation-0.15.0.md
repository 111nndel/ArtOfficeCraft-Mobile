# English UI and document gestures — 0.15.0

The approved HTML v1.3 and expandable tool-slab navigation are unchanged.

## Changes

- English and Russian UI, Android system-language selection, and an app-private
  persisted override in About. Flutter Material controls use the matching locale.
  The catalog contains 358 unique entries, including all 104 tool/section labels.
- Translation is applied only at UI boundaries. Document content, existing file
  names, user-defined sheet names and native operation IDs remain unchanged.
  English template seeds apply only when creating new sample documents.
- Sheet pinch zoom (50–300%), one-finger pan and viewport-based row construction.
  Column headers stay visible. Formula input and tools retain their size. Presets
  are connected inside View / Zoom, and a new workbook resets the viewport.
- PDF now starts at page width in the full available canvas. Pan/pinch work on the
  whole viewport, thumbnails are initially hidden and can be toggled, and Read /
  Zoom offers Fit width and Fit page. Rotated pages swap canvas dimensions.
- Scale matrices use matching X/Y/Z scales so InteractiveViewer correctly reads
  and constrains reductions below 100%, including the initial PDF width fit.
- Editors respect the Android status-area inset when the tool slab hides their
  app bar. Zoom presets preserve the sheet viewport origin; pinch keeps its own
  gesture focal point. A regression covers the status-area clearance.
- CONTRIBUTING.md explains how to fork this independent mobile repository while
  preserving upstream provenance, license notices and the interaction contract.

## Validation

- Flutter analyzer reports no issues; all 80 unit/widget tests pass. New tests
  cover pinch/pan and row culling with touch selection, full-width tall PDF and
  fit-page/reset, persisted language choices, English Home/nested tools, complete
  tool-label coverage, and preservation of Russian filenames/content/cell input.
- Three real-engine integration scenarios pass on Android 16 API 36 x86_64.
  Existing editing/roundtrip paths and fresh-store draft recovery pass for all
  four engines. The English scenario verifies retained Russian document text,
  pending spreadsheet input through pinch and a 150% preset, initial PDF width
  fitting, PDF pinch and the thumbnail control.
- The ordinary offline x86_64 profile app passes tools/test_mobile_ux.js. Russian
  and English overrides survive actual Android force-stops, About retains the
  explicit English selection, and the PDF opens with its English counter and
  thumbnails hidden. The English Home and PDF canvas were visually inspected.
- tools/test_recovery_force_stop.js also passes on the ordinary app in English:
  exact unapplied text survives force-stop and is reopened through Home recovery;
  explicit discard removes its recovery entry. That tool now accepts both UI
  languages. Ordinary-test APK SHA-256:
  `b312d220ea23c90c9cec496bfc696e7d7b9a24559665bbf147b4dea5a56cfdaf`.
- An additional ordinary-app GUI smoke selected A1 by touch, entered and applied
  a real cell value, opened View / Zoom / 150%, captured the enlarged sheet, and
  explicitly discarded the test workbook. The sheet screenshot was inspected for
  status-area clearance, visible A1 and the retained large formula/tools.
- All 121 normalized build/test/source files match the build PC. Flutter SDK
  3.47.9 with Dart 3.13.7 was used for final tests/builds.
- Final ARM64 split profile APK: 38,269,646 bytes, versionCode 2021 (base 21),
  versionName 0.15.0. SHA-256:
  `1f6429199a68caf88ee7111595c250641de99ed7e490e6f7181256b230f0093c`.
  ZIP integrity, ELF/ZIP 16-KiB alignment, offline permission and signature checks
  pass; all 94 Rust dependency licence texts are bundled. The development signing
  certificate matches earlier previews (SHA-256
  `4e16cc21d19cdcde840361cd34fbdcfbf901b48c6f8ff66ef473e7ddf4a05005`).
- Rust adapters/core 0.13.0, ABI 1 and all upstream revisions are unchanged. The
  previously passing 17 Rust tests were not rerun for this Flutter-only change.

## Limits

No physical Vivo or runtime 16-KiB-page test was performed. The sheet preview is
still bounded to 55 rows x 12 columns and inspection to 1600 populated cells per
sheet. Zoom does not remove those limits or add complete Excel rendering. Viewport
position/zoom is session-local. PDF raster resolution remains bounded (normally
1000 px wide); enlargement does not provide unlimited detail. Low-level engine
error details may remain in their original language. Complex Office rendering
and unsupported editing commands retain the earlier limitations.

Recovery restores only the last written checkpoint, without session-local undo
history. Cancellation and Save As behavior are unchanged.
