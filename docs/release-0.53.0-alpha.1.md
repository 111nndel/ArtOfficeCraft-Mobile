# ArtOfficeCraft Mobile 0.53.0

## What's New

- Excel Home / Fill range adds Fill down and Fill right. Select the source
  row/column together with the destination; formulas and formatting are copied,
  relative references adjust, and absolute references remain fixed. Rows hidden
  by a filter stay unchanged. Pending input and filling form one undo step;
  redo and Save As retain the result.
- Fill uses GridCraft's existing command engine through the existing worker and
  ABI. Each operation is limited to 4096 cells and the undo memory budget.
  Protected sheets, merged cells, Excel tables and array/spill ranges are refused.
- Updated all four reviewed source pins: WordCraft 0.18.1, GridCraft 0.19.1,
  DeckCraft 0.18.1 and PDFCraft 0.21.1. These releases include calculation,
  file-compatibility, bounded-work and PDF rasterization fixes. Desktop-only
  features are not automatically exposed in the mobile editors.
- PDFCraft's URL parsing adds nine Rust packages for URL/Unicode handling;
  existing registry versions are retained. Document processing remains local.
  No new Flutter packages, Kotlin handlers or Android permissions.
- Native core 0.53.0, ABI 1. App 0.53.0+60 (ARM64 versionCode 2060).

## Known Limitations

- Directional fill repeats the first selected row or column. Automatic numeric
  or date series and drag-to-fill are not included in this release.
- The existing preview/editor fidelity limits remain. New upstream desktop
  functionality is available only when a corresponding mobile adapter is implemented.
- Updates from 0.52.0 can be checked manually or downloaded automatically on
  launch/resume; Android confirms installation. Published APKs target ARM64.
- Preview signed with the existing development certificate.
