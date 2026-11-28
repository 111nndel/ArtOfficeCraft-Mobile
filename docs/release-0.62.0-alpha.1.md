# ArtOfficeCraft Mobile 0.62.0

## What's New

- PowerPoint reuses embedded images from the initial slide preview. It can display cached images and thumbnails without importing the PPTX again on every request.
- PowerPoint's slide search can include speaker notes. Results from notes are marked and open the matching slide.
- Verified the current stable upstream versions. WordCraft, GridCraft and DeckCraft use 0.19.1. PDFCraft uses 0.22.0.
- App 0.62.0+69, Android ARM64 versionCode 2069. Native core 0.62.0, ABI 1.

## Known Limitations

- Speaker notes search covers notes available in the preview, up to 64 KiB per slide and 2 MiB per presentation.
- The native image cache retains up to 16 MiB of raster data per presentation and serves up to two open presentations. The regular image loader handles cache misses.
- The Android preview targets ARM64 devices.
