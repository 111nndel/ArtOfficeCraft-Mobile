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

## Six-page image comparison

The first image-fidelity run compared the same original PDF at 144 dpi with
Poppler 24.02.0 and the pinned PDFCraft CPU renderer. The fixture embeds DejaVu
regular/bold/italic TTF subsets and contains only original graphics and labels.
Its font hashes and licence notices are retained with the evidence.

[First six-page run and raster pairs](https://github.com/111nndel/ArtOfficeCraft-Mobile/actions/runs/42575413644)
using app probe source `eaeb9c2529db4d29846b72e75117783f1b48778c`:

| Case | Raster size | Mean absolute channel error, 0-255 | Pixels with a channel difference >32 |
| --- | --- | ---: | ---: |
| Embedded Cyrillic TTF styles | 1200 x 1600 | 0.520 | 0.526% |
| JPEG raster document | 1200 x 1600 | 0.840 | 0.957% |
| PDF alpha and RGBA PNG | 1200 x 1600 | 0.367 | 0.283% |
| Vector clipping | 1200 x 1600 | 0.766 | 1.075% |
| 90-degree page rotation | 1600 x 1200 | 0.361 | 0.323% |
| Offset CropBox | 1040 x 1400 | 2.059 | 2.007% |

All six sizes matched without resizing; all 13 content regions passed the
fixed comparison policy. Region dark-pixel ratios ranged from 0.973 to 1.038,
and the largest regional mean channel error was 5.108. The renderer reported
zero warnings. Peak process RSS for this six-page run was 42.8 MiB. Raster pairs
were also visually reviewed; no missing text, graphics or misplaced page boxes
were observed in these cases. Pixel differences remain, including antialiasing
and image resampling, so this is not a pixel-identity claim.

`tools/pdf_fidelity/` keeps the fixture generator, exact comparison policy and
seven tests against false-positive comparisons. Its workflow also provides a
separate Android PdfRenderer comparison using the same fixture and reference;
those results are recorded independently in the Android job's evidence.

## Integration decision

Keep this as a development-only probe. Before selecting it as an application
renderer, complete the Android image comparison and broaden document coverage
to large or malformed PDFs, forms, CFF/Type 3 fonts and complex colour spaces.
Then measure native ABI transfer, Flutter display/cache memory
and lifecycle cleanup on Android ARM64 and an actual desktop runner.

The current shared `PdfPageRenderer` contract provides a replacement boundary.
Adding the new renderer should include bounded session ownership, cancellation,
input/pixel limits and explicit OCR capability handling. A new backend should
be introduced after those checks rather than as another appearance setting.
