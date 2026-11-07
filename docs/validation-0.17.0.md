# Appearance persistence and XLSX windowed view — 0.17.0

## Change

The old app unconditionally started with ThemeMode.light. An independent
appearance.json preference now uses serialized, flushed, atomic replacement.
Startup loads it before runApp. Revision checks prevent a late load or rapid
choices from replacing the latest selection. Save failures are surfaced.
Old releases stored no preference, so the desired theme must be selected once.

The sheet previously mounted 55 rows / 12 columns and relied on a global
first-1600-populated-cell preview. The mobile editor now uses additive
ac_xlsx_inspect_window (ABI 1) and a bounded two-axis virtual view. Windows are
normally 64 x 16, grow for larger visible areas, and cannot exceed 128 x 32 /
4096 cells at the native boundary. Excel bounds are 1,048,576 x 16,384.
The selected-cell value is returned independently of the visible rectangle;
loading a different rectangle never assigns to the input controller.

Pan requests are debounced/coalesced. Failed reads show a retry control rather
than treating unread data as empty; old bytes, selection and pending input remain
available. An edit plus window inspection is one worker transaction; history is
advanced only after both succeed. Known immutable input uses the existing worker
cache. Headers stay visible on both axes. Go to cell is a nested View form in the
approved slab. Long-press selects a cell and focuses the formula input.

## Validation

- Clean Flutter analysis; 98 unit/widget tests pass. Regressions cover preference
  restart/races/first frame, two-axis mounting bounds, the last Excel address,
  invalid navigation preserving input, far-cell edits/undo and failed area reads.
- All 19 Rust tests pass. New native cases find populated cells beyond the
  legacy cutoff in a dense 2500-cell sheet, inspect XFD1048576, return the selected
  cell outside a rectangle, and reject invalid/oversized bounds and addresses.
- Five Python tests pass, including bounded retries of corrupted SDK downloads.
  A later 0.16.0 branch CI run failed on a truncated NDK ZIP; hosted SDK installs
  now retry up to three times and discard incomplete temporary downloads.
- Six real-engine scenarios pass on the dedicated Android 16 API 36 x86_64
  emulator. Existing four-engine editing, recovery, English/gestures, worker
  lifecycle and PPTX picture tests remain passing. The new scenario commits A1
  while navigating through View to AA1000, recalculates an off-screen reference,
  keeps pending formula input during pans, exercises undo/redo and inspects actual
  exported XLSX bytes (AA1000 = A1*4, displayed 60). Original input still displays
  42. The export dialog is mocked in this integration scenario.
- An ordinary offline x86_64 profile APK passes the independent theme script:
  actual rendered pixels remain dark across three Android force-stops and a
  Back exit; light also persists after restart. Dark Home was visually inspected.
- The ordinary profile app also navigated to AA1000 through actual Android
  touch/text events, applied =20+22 and displayed 42. The distant cell, headings
  and formula strip were visually inspected; explicit discard returned Home.

## Limits

This is windowed data/display, not a retained parsed native workbook. Every
native view request still parses the complete XLSX, so large-file latency/native
memory and cancellation need further work. Only current/cached formula results
are displayed until recalculation by editing. A read window is not a process
sandbox or a whole-app memory limit.

Row/column dimensions remain uniform, merged areas/images/charts are not rendered
faithfully, range operations and many tools remain unavailable. There is no claim
of full Excel or other Office-editor parity. No physical Vivo or runtime 16-KiB
page test was performed. Upstream engine pins and dependencies are unchanged;
only the mobile adapter core version changes to 0.17.0 (ABI 1).
