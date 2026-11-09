# Portable PDF rendering: first feasibility check

The current APK keeps Android PdfRenderer. The existing PDFCraft render crate
was built and measured separately; it is not linked into the application.

## Source and method

- PDFCraft `v0.19.0`, exact commit `8c572792d6760bdc903d6f9a032e3e38e8f71cb8`.
- Upstream `pdfcraft-render` currently wraps Hayro (interpretation and Vello CPU
  rasterization), with PDFCraft font and inspection code. Portability would add
  renderer dependencies to our core; it does not remove all dependencies.
- Linux x86_64 GitHub runner, Rust 1.99.1, release build, one rendering worker.
- Upstream `synth_sheet` generates a rotated vector PDF with 10,000 strokes and
  1,143 Latin labels. No user documents enter the workflow.
- Each scenario runs three rounds in one process. GNU time measures peak process
  RSS across those rounds. Pixel-result hashes must remain equal and every round
  must report zero errors; warnings are retained in the measurements.
- The `load` case starts a pool with no render requests, so it measures setup
  overhead and is not a full document-parsing benchmark.

## Observed results

[Reproducible workflow and full evidence](https://github.com/111nndel/ArtOfficeCraft-Mobile/actions/runs/42544214244)
using app probe source `66091691b1960855eef29fa1f74da16bc49c0bbf`:

| Scenario | First round wall time | Later rounds | Peak process RSS |
| --- | ---: | ---: | ---: |
| Pool setup, no requests | 0 ms | 0 / 0 ms | 5.7 MiB |
| Thumbnail | 27 ms | 26 / 26 ms | 11.6 MiB |
| Page backdrop, longest side 2048 px | 40 ms | 39 / 34 ms | 24.0 MiB |
| Four 1024 px tiles at 100% | 59 ms | 58 / 59 ms | 24.6 MiB |

All four scenarios completed with zero reported errors and warnings. Hashes
matched within each scenario across three rounds. These are measurements for
one synthetic fixture on one Linux runner. No Android speed, battery, APK-size
or visual-fidelity comparison was performed. Deterministic hashes do not prove
that a page is rendered correctly.

## Integration decision

Keep this as a development-only probe. Before selecting it as an application
renderer, compare page images with Android and an independent reference using
embedded Cyrillic fonts, scanned images, transparency, rotation and large or
malformed PDFs. Then measure native ABI transfer, Flutter display/cache memory
and lifecycle cleanup on Android ARM64 and an actual desktop runner.

The current shared `PdfPageRenderer` contract provides a replacement boundary.
Adding the new renderer should include bounded session ownership, cancellation,
input/pixel limits and explicit OCR capability handling. A new backend should
be introduced after those checks rather than as another appearance setting.
