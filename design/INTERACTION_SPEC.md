# Approved mobile design

The design reference is `design/ArtOfficeCraft_Mobile.html`, version 1.3,
approved by the project owner on 2026-11-03. Complete this design migration before
adding missing editor capabilities. Do not redesign the navigation during engine
integration.

- Each editor has one bottom tool slab. There is no fixed count of shortcut icons,
  horizontal tool ribbon or separate More sheet.
- Tapping the current section caption itself opens the full section menu above
  the same slab. The chevron expands/collapses the slab independently.
- Nested lists and forms replace the slab contents, with Back restoring the parent
  and its scroll. Collapsing retains the active pane, input and canvas state.
- The document remains mounted while navigating tools. Expanded tools yield
  header space; controls remain at least 52 logical pixels tall.
- Word, Grid, Deck and PDF share this navigation model, but their section names,
  ordering and tool inventories follow their respective reference modules.
- File commands live in the file header menu. Grid has its own independent formula
  strip and sheet tabs. Slides/PDF keep their document-specific thumbnails.
- Unimplemented commands are explicitly unavailable and labelled as not connected.
  Do not simulate document changes or attach placeholder success messages.
- The native content renderer retains its existing limitations. Changing its layout
  fidelity or adding Rust document operations is a later implementation stage.
