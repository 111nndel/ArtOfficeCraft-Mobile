# ArtOfficeCraft Mobile 0.42.0

> Android ARM64 development preview.

## What's New

- PDF pages and thumbnails now render through PDFCraft Rust and the existing background document worker. A parsed document stays open between page requests.
- Raster sessions use opaque IDs, explicit close, bounded page dimensions and a two-document limit for safe replacement. Closing an editor discards stale results and drains its worker.
- Android PdfRenderer remains a lazy compatibility fallback; the same adapter supplies local English/Russian OCR. No new Kotlin handlers, online service or Flutter dependencies were added.
- The image-fidelity harness now calls the real application C ABI on Linux and Android. It adds original Type3 vector glyphs and AcroForm appearances to the prior six synthetic cases and disables fallback for native evidence.
- Bundles 219 resolved Rust packages instead of 168: the added local renderer, font/image codecs and their dependencies carry their licence notices, including embedded standard-font substitutes.
- Retains WordCraft 0.17.0, GridCraft 0.18.0, DeckCraft 0.17.0 and PDFCraft 0.20.0 at the reviewed source pins from 0.41.0. Native ABI remains 1.

## Known Limitations

- This changes PDF display, not the set of PDF editing tools. Full forms editing, digital signing and arbitrary document fidelity remain incomplete.
- CFF fonts, complex ICC/spot colour and more real documents still need compatibility testing. A successful synthetic comparison is not proof that every PDF renders correctly.
- Android remains the only packaged Flutter target. Portable Rust rendering and Linux worker checks do not establish complete desktop application support.
- Runtime checks use an Android 16 x86_64 emulator; the downloadable APK is ARM64. No physical Vivo test is claimed.
