# ArtOfficeCraft Mobile 0.44.0

> Android ARM64 development preview.

## What's New

- XLSX viewport queries, selected-cell reads, search batches and filter choices reuse a parsed Rust workbook instead of opening the same ZIP for every request.
- Each background worker owns its read session. Switching input snapshots, editing, copying/pasting and closing releases that model. Undo/reopening reads the requested version.
- At most two parsed reader models are retained process-wide. Additional workers use the existing stateless path without evicting an active reader.
- Adds lifecycle/equality tests and a reproducible 100,000-cell host benchmark. Timing is reported without a flaky speed threshold; output differences fail the check.
- Native core 0.44.0, ABI 1. Engine source pins and the 219-package Rust dependency graph are unchanged; no runtime dependency, Kotlin code or interface setting is added.

## Known Limitations

- The current parsed workbook uses memory while reading; it is released before stateless edits. The cache has a model-count bound, not a promise about peak memory for arbitrary XLSX input.
- Opening a document and applying edits still parse its XLSX. Layout metadata and requested cells are still produced for each window. This does not remove every source of spreadsheet latency or improve DOCX/PDF rendering.
- Benchmark timing describes a synthetic workbook on a Linux CI host, not phone FPS or a measured physical-device speedup.
- Android remains the only packaged target. Runtime checks use an Android 16 x86_64 emulator; physical-device validation is separate.
- Existing document-fidelity and editing limits remain in effect.
