# ArtOfficeCraft Mobile 0.54.0

## What's New

- Home / Recent file actions adds Clear all recents and document selection.
  Long-press a recent card to select it, select more cards or all visible
  records, then Remove from recents. Selection actions stay in the top bar
  while scrolling; Android Back cancels selection. Removal offers Undo.
- Clear all asks for confirmation and clears recent records across every
  format, even when a format filter is active. Select all applies to the
  visible format. Navigation, search and filter changes end selection.
- Clearing history keeps the working copies in Files, favorites, and recovery
  drafts. Reopening a retained document brings its existing record back to
  Home. No filename-based merging or deletion of document bytes.
- History changes are serialized with imports and favorite changes and
  committed through the existing atomic index write. Older installations
  retain their history on upgrade.
- Russian and English actions support narrow screens and enlarged text.
  Files now labels the retained documents as Working copies.
- App 0.54.0+61 (ARM64 versionCode 2061). Native core 0.53.0, ABI 1;
  WordCraft 0.18.1, GridCraft 0.19.1, DeckCraft 0.18.1, PDFCraft 0.21.1.
  No new dependencies, Kotlin code, Android permissions or native libraries.

## Known Limitations

- Removing from recents does not free document storage. Working copies remain
  available in Files. Recovery drafts have their own explicit delete action.
- Undo is available while its snackbar remains visible. A retained copy can
  always be opened again from Files.
- The existing editor format and rendering limits remain. Published APKs
  target Android ARM64 and use the existing development certificate.
