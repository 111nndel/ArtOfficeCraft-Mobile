# ArtOfficeCraft Mobile 0.56.0

## What's New

- Recent-history feedback now closes automatically after five seconds and has
  a close button. Leaving the recent list or opening a document dismisses it
  immediately. Late history writes cannot show that message over another screen.
  Undo remains available while the message is visible; closing it keeps the
  entries hidden and retains the document copies, favorites and drafts.
- The update-ready notification also has a close button and a finite timeout.
- Excel Find adds Match case and Match entire cell. Both work with displayed
  values or formula text, on the current sheet or across the workbook. Existing
  Unicode matching, search batches and protected-formula handling remain.
- Point lookup in merged worksheets no longer allocates and sorts a match list
  for each cell. Imported first-match behavior is preserved even for overlaps.
  The existing benchmark now records point-query timings and checks equal output.
- The four Rust document bridges and build information share one ABI result
  layout, bounded result copying and guaranteed Rust-buffer release. Duplicate
  ABI checks and clipboard guards below the supported Android minimum were removed.
- No new dependencies, plugins, Android permissions or native libraries.
  Document processing remains local.
- App 0.56.0+63 (ARM64 versionCode 2063), native core 0.56.0, ABI 1.
  Reviewed engine pins remain WordCraft 0.18.1, GridCraft 0.19.1,
  DeckCraft 0.18.1 and PDFCraft 0.21.1.

## Known Limitations

- Search is literal. Case-insensitive matching uses Unicode lowercasing;
  whole-cell matching includes spaces and displayed number formatting.
- Benchmark timings are host measurements, not Android UI frame rates.
- Existing editor and format limits remain. APKs target Android ARM64 and use
  the existing development certificate.
