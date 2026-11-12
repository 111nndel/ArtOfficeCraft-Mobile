# ArtOfficeCraft Mobile 0.50.0-alpha.1

## What's New

- Spreadsheet layouts build one lazy, immutable merge index. Viewport queries,
  reduced-zoom painting, cell selection and range expansion use it instead of
  repeatedly scanning every imported merge.
- Compact rendering retains that index while preview row/column sizes change,
  and reuses the resolved merge when calculating a cell rectangle.
- Read-only viewport responses reuse the current sheet geometry. Document edits,
  undo/redo, new files and sheet changes replace it together with the cell cache.
- Inclusive merge bounds, original document order, partially visible anchors,
  hidden lines, merge fills and touch editing remain covered by regression tests.
- CI records an AOT comparison with the previous linear scan on 10,001 synthetic
  merges, including a merge spanning all rows, and checks exact output equality.
- No new dependencies, native libraries or Kotlin code. Native core 0.49.0 and
  the four pinned document engines are unchanged.

## Known Limitations

- Host benchmark results describe merge lookup, not Android frame rate or whole
  workbook load time. Large numbers of merges sharing the same rows can still
  require checking many candidates.
- Imported office layout remains approximate; this change does not provide a
  complete Excel or Word layout engine.
- Preview release signed with the existing development certificate.
