# ArtOfficeCraft Mobile 0.60.0

## What's New

- Word, Excel, PowerPoint and PDF update Recents without rewriting a working copy when it is reopened. Input-only recovery checkpoints keep their existing document and skip scanning the recovery folder.
- PowerPoint continues loading embedded pictures after the first twelve. Mounted pictures reuse their load during selection and object editing, and thumbnails use smaller decoded images.
- PDF and PowerPoint can jump to a page or slide by dragging a slider in the page or slide number panel. The editor jumps when the slider is released. The number field supports precise jumps.
- PDF transfers the document and rendered images between isolates using transferable buffers. The Rust rasterizer and OCR remain available offline.
- App 0.60.0+67, Android ARM64 versionCode 2067. Native core 0.59.0, ABI 1.

## Known Limitations

- The PowerPoint preview supports embedded PNG, JPEG and WebP pictures up to 8 MiB each. Rendered shapes and images follow the preview's existing format limits.
- The Android preview targets ARM64 devices.
