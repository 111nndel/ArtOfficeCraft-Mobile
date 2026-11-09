# Approved mobile design migration — 0.12.0

The HTML v1.3 reference is unchanged. Its navigation is now implemented by the
shared Flutter EditorToolPanel; section names and command ordering are recorded
in office_tool_sections.dart. See design/INTERACTION_SPEC.md.

The panel has one persistent header, a caption-driven anchored section menu,
vertical tools and nested inline forms. Visited panes retain their state and
scroll controllers. Expanding hides the file header without unmounting the
canvas; collapsing retains the pane. Android Back closes the section menu,
returns to its parent, then collapses the slab before leaving the editor.

The slab uses Scaffold's bottom-navigation slot with keyboard insets, so a save
notification no longer covers Undo/Redo. File operations have one header menu.
Grid formula expansion is independent, and sheet tabs are retained. Deck text
editing now uses a persistent form in the slab. Failed edits keep its draft;
Save As applies pending text before serializing the current file. Missing
commands are explicitly disabled, rather than returning fake success.

## Validation

- Flutter analyzer: no issues. All 53 widget/unit tests pass on the final source.
- Interaction regressions at 320, 393 and 800 logical pixels tap the actual section
  caption, navigate nested forms, collapse/reopen, retain a field value and root
  scroll, and verify the same canvas state. Existing large-text and keyboard
  portrait/landscape cases pass.
- Added Word regression: format, continue typing, collapse tools, open the file
  menu and export the current draft. Existing failed-edit and repeated-export
  protections still pass.
- Real pinned Rust engines pass the Android 16 API 36 x86_64 integration scenario:
  DOCX selection/style plus continued Unicode input and file export/reparse,
  undo/redo, XLSX formulas and editing, PPTX insertion through the slab text form,
  native PDF viewing and fresh filesystem roundtrips. Screens were inspected for
  the home, caption menu, Word controls and Deck's inline text form.
- This export test substitutes Android's Save As channel with a test file writer.
  It does not retest the interactive SAF picker or a physical Vivo. Continuing
  typing after formatting explicitly taps the document to return keyboard focus.
- The final cosmetic pass adds the home brand mark, visible grid boundaries and
  module-coloured form controls. The final widget suite and analyzer were rerun.
- Final ARM64 split profile APK passes ZIP integrity, ELF/ZIP 16-KiB alignment,
  bundled Rust licence checks (94 packages), Android signature verification and
  permission inspection. No INTERNET or Wi-Fi permissions are present. The
  development certificate matches the previous preview.
- APK: 37,466,210 bytes, versionCode 2018 (base build 18), SHA-256
  `27049d4a4dcd31999afb41b95ff439b5003a8bd432191d7774d707f5cc02fd19`.

The native ABI, core 0.10.0 and pinned upstream revisions are unchanged. Rendering
remains approximate: this release migrates the controls and layout, not Office
pagination or missing document engines. Unsupported formatting, document-wide
selection, complex presentations, PDF editing/OCR and process-death draft
recovery remain incomplete. Runtime 16-KiB memory pages and physical Vivo hardware
have not been tested. The downloadable profile build is a development preview.
