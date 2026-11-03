# 0.11.0 inline DOCX editing — 2026-11-03

DOCX ordinary paragraphs now become editable on the document canvas. The native
document model remains separate from the active Flutter text draft. No parsing
or serialization is requested for each keystroke. Only one paragraph is active.

Done, switching paragraphs, formatting, undo/redo, opening another document and
Save As commit the draft before using the document bytes. Failed native edits
retain the current input, keep the document dirty and block stale-byte exports.
Repeated file commands are serialized. A newly appended blank paragraph opens
directly on the page.

Selected bold/italic/underline and justification are reachable above the
keyboard. With no selection, character buttons explicitly name the entire
paragraph as their target. The separate Formatting panel preserves the inline
UTF-16 selection and retains font size, alignment and line spacing controls.
It does not display a second text editor.

## Validation

- Flutter analysis: no issues.
- 49 Flutter widget/unit tests pass. New cases cover local typing without native
  calls; Save As flushing the visible draft; retaining failed edits and preventing
  stale export; repeated Save commands; mixed Unicode style runs and IME composing
  ranges; large-text keyboard layouts in portrait/landscape; and selection-aware
  advanced formatting without a second text field.
- The Android 16 API 36 x86_64 scenario uses real pinned Rust libraries. It changes
  text on the page, applies italic to a selected range, types an additional emoji
  suffix, exports before Done, then reads the DOCX and checks both text and style.
  It also checks undo/redo and the existing XLSX/PPTX/PDF paths.
- That export check substitutes the platform Save As channel with a test file
  writer on Android. It verifies native bytes and disk readback, not the interactive
  Android SAF dialog itself. Original documents are never replaced by the test.

The upstream Rust commits, native ABI and core version remain unchanged from
0.10.0. Only the Flutter app version advances to 0.11.0+16. Downloadable builds
use optimized profile mode and the existing development certificate. The normal
offline manifests are restored after the separate debug test build.

## Limits

This remains a flow preview of ordinary paragraphs, not a complete paginated Word
layout or a single selection spanning several paragraphs. Enter inserts a line
break within the active paragraph; the New paragraph command appends a separate
paragraph. Tables, floating objects, inherited complex styles and document-wide
editing still need work. Protected/revision/object-bearing paragraphs stay
read-only. Formatting at a collapsed caret applies to the paragraph, rather than
setting a future typing style. Failed drafts survive within the editor session;
they are not yet recovered after Android kills the app process.

XLSX/PPTX/PDF capabilities are unchanged. Native operations still serialize a whole
file per commit, so large-file profiling and persistent native sessions remain
future work. No physical Vivo or 16-KiB runtime test has been performed. ELF/ZIP
alignment and offline permissions must be checked on the final ARM64 APK.
