# ArtOfficeCraft Mobile 0.55.0

## What's New

- PDF requests a fresh raster of the visible area at the current screen density
  and zoom. Enlarging a page no longer relies solely on stretching its fixed
  preview. Both single-page and continuous reading modes refine their view.
- The existing page preview remains visible during refinement. Pan and zoom
  requests settle before rendering; each visible page keeps one render in
  flight and uses the latest demand. Replaced documents cannot show late images.
- PDFCraft's existing tile API draws the detail crop through the existing Rust
  worker and ABI. Every crop retains the 4.2-million-pixel and 2880-pixel-side
  limits; the app does not allocate the complete enlarged page. Superseded
  detail images are evicted from the Flutter image cache.
- The existing thin Android compatibility adapter also supports bounded crops.
  No new Flutter/Rust dependencies, Android permissions, plugins or native
  libraries. All document processing remains local.
- Recent-history cleanup from 0.54.0 remains available with selection, Clear all
  and Undo. Working copies, favorites and recovery drafts are retained.
- App 0.55.0+62 (ARM64 versionCode 2062). Native core 0.55.0, ABI 1;
  reviewed engine pins remain WordCraft 0.18.1, GridCraft 0.19.1,
  DeckCraft 0.18.1 and PDFCraft 0.21.1.

## Known Limitations

- A low-resolution scanned source cannot gain detail beyond its original image.
  Viewports exceeding the raster budget use a bounded detail resolution.
- Refinement follows a short gesture-settling delay. Unsupported detail rendering
  retains the available preview. Existing format and editor limits remain.
- Published APKs target Android ARM64 and use the existing development certificate.
