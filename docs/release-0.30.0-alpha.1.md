# ArtOfficeCraft Mobile 0.30.0 — touch editing and larger Word documents

> Android ARM64 development preview.

## What's New

- In PowerPoint, tap Edit objects and drag a supported shape or picture. Select an object and pull its corner handle to resize it. Geometry changes save to PPTX and support undo and redo.
- In Word, paragraphs are built lazily as they approach the viewport. Search can jump to a far match while keeping earlier and later paragraphs scrollable.
- In PDF, Comments → Comment adds a text note to the current page. All comments lists text notes, and saved copies retain standard PDF annotations.

## Known Limitations

- Object editing supports unlocked, unrotated shapes and pictures at the slide's top level. Complex groups and exact PowerPoint rendering remain in progress.
- Word uses continuous text layout. A DOCX edit still requires serializing and reopening the document model on the worker.
- PDF notes are annotations. Editing existing page content remains in progress.
- Android runtime validation uses an emulator.
