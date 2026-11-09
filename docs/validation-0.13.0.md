# Reliable XLSX editing and native cell styles — 0.13.0

The approved HTML v1.3 and mobile navigation contract are unchanged. Existing
Main/Cell format, Fill and Borders panes now invoke native operations instead
of placeholder actions. Missing capabilities remain explicitly unavailable.

## Changes

- Grid's pending input participates in the dirty guard. Save As, cell selection
  and sheet switching flush the old address before proceeding. Errors retain the
  draft, selection and previous bytes and prevent stale exports.
- Cell formatting and any pending value are one atomic native request and undo
  step. History is updated only after new bytes parse successfully; a failed
  restore does not consume the undo/redo target. Undo first cancels unapplied
  input. Applied edits refresh the app-private working copy when available.
- The Rust adapter preserves style ids on value/formula replacement and clear.
  It clones existing styles for partial changes, uses the upstream style table,
  rejects protected sheets/invalid requests and serializes through GridCraft XLSX.
- Font emphasis/size/colour, solid fill, thin/clear borders, alignment, wrapping
  and number formats are persisted and included in inspection. The pinned
  gridcraft-numfmt crate produces the displayed numeric value, separately from
  the formula-bar input. Text-formatted input retains leading zeros and literal
  formulas; decimal-comma numeric input is accepted.
- Font controls show active emphasis. Existing Word controls use the same active
  state without changing the panel layout.
- PDF renderer replacement closes the previous Android document session after
  the new one opens; disposal closes the current session.

## Evidence

- Clean Flutter analysis; all 60 widget/unit tests pass. New regressions cover
  save without the checkmark, failed edits/stale-export prevention and retry,
  dirty cell/sheet navigation, atomic format+value, undo/redo after failed inspect,
  draft cancellation and the PDF session lifetime.
- All 17 Rust tests pass. Added XLSX roundtrips inspect stored styles after value,
  formula and clear operations, verify numeric display and unchanged underlying
  values, preserve text-formatted zeros/formulas, and reject invalid patches.
- Four updater tests pass; the source sync validates all four pinned upstream
  checkouts. gridcraft-numfmt is an explicit dependency from the existing GridCraft
  pin. Engine repository revisions are unchanged; adapter core is 0.13.0, ABI 1.
- The Android 16 API 36 x86_64 integration scenario passes the existing four-engine
  paths and the new Grid flow: decimal-comma entry, bold and percentage through
  nested panes, continued input, Save As before checkmark, native reread of 75.00%
  with the style retained, then undo/redo. The percentage pane was visually checked.
  Export uses a test Save As channel; this is not a new manual SAF-picker test.
- Final ARM64 split profile APK: 37,548,502 bytes, versionCode 2019 (base 19).
  SHA-256: `a4f9c71cbac419a9d5d9c1f0029e9b5edab1262c441b7fa6ed4d4cc7c9257404`.
  ZIP integrity, ELF/ZIP 16-KiB alignment, development signature and offline
  permission checks pass. Resolved licence texts cover 94 Rust packages.

## Limits

No physical Vivo or runtime 16-KiB-page test has been performed. Number formatting
uses the pinned engine's format renderer and its locale limitations. Complex
spreadsheet features and imported style combinations are not fully rendered.
The viewport remains 55 x 12, inspection is bounded to 1600 stored cells per sheet,
text wrapping is clipped to the current fixed row height and undo history is
session-local and bounded. Working-copy updates apply to successfully committed
Grid edits; unapplied drafts are not recovered after Android kills the process.
Exact Office pagination and missing Word/PPTX/PDF capabilities remain incomplete.
