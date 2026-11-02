# Mobile usability requirements

This is a checklist for **actual Android UX tests**, not a claim of complete functionality.

## Navigation and clarity
- The start screen must name what tapping a card does. It opens an editor; it does not silently create a file.
- Never advertise unavailable DOCX/XLSX/PPTX/PDF features as implemented.
- Do not duplicate navigation lists that lead to identical screens.
- Explain the difference between opening an existing document and creating a new one.
- Show only important contextual information while retaining maximum document canvas area.

## Touch and accessibility
- All primary interactive controls should have a touch target of at least **48 dp**.
- Show readable text labels for editing commands; do not rely on icons whose meanings are ambiguous.
- Test widths 320, 360, 393, 412 dp and common landscape configurations.
- Avoid text/clipping overflow at enlarged system font sizes.
- Keep essential commands usable one-handed in portrait mode, preferably near the bottom.
- Provide semantics/tooltips for icon-only actions, and visibly disable unavailable actions.

## Document safety
- Save a **new copy**, never overwrite an imported original without explicit confirmation.
- Confirm destructive operations (e.g. delete a page) and warn before discarding unsaved changes.
- Disable repeated taps while work is ongoing, report errors in understandable language.
- Existing PDF, Office formatting and unsupported elements must not be silently misrepresented as editable.
- Keep local document bytes private, without Internet or Wi-Fi permissions.

## Performance and real-device testing
- Rendering, parsing and media extraction should not block Flutter's main frame thread.
- Avoid reopening a whole PDF for every page; bound image caches and decoded dimensions.
- Check homescreen, file picker, keyboard, text editing, Save As and reopen on Android emulator.
- Recheck physical ARM64 phone workflows when a device becomes available.
- Treat any untested screen, button or feature as unverified, not complete.

## Change acceptance
For every UX adjustment: run Flutter analyze and automated widget tests; review
a narrow phone layout, and where practical run the new flow on Android before
claiming it has passed. Prefer measured task completion and readable controls
over decorative layout changes.


## 0.8.2 editor audit (320 dp QA emulator)

- DOCX: two bottom controls now stack full-width when the available
  width is below 440 dp, each at least 48 dp high. The editor's preview
  was opened with a newly created document in Android 15 QA. The
  keyboard-open workflow remains unverified because the QA emulator
  exited during the follow-up input test.
- XLSX: spreadsheet cells and row/column headers are 48 dp tall;
  values use 13 sp text. Sheets controls are 48 dp tall, with a
  horizontal action strip and unambiguous New workbook / Save copy.
  The formula bar now has a short input hint with an accessible tooltip
  describing the "=" syntax. A new workbook was opened on a 320 dp
  simulated Android 15 screen and the resulting layout examined.
- PPTX: the bottom actions are 48 dp high, labelled New slide, Add text,
  Save copy, and horizontally scroll. A new Android GUI test of these
  controls is still outstanding after the QA emulator exited.
- PDF: the labelled 48 dp scrolling bottom bar from 0.8.1 is retained.

The separate ToTstore emulator was not modified. The QA emulator had
its screen resolution temporarily overridden for narrow-screen tests;
it exited unexpectedly during DOCX keyboard testing. Do not infer the
physical-phone result from these emulator tests.

## 0.8.3 large text and keyboard acceptance

- Main editor cards: 320 dp, Flutter text scaling 160% and 200%.
  Cards increase in height; the intro becomes shorter. No overflow.
- DOCX: Android 15, 150% text scaling, new document, keyboard entry,
  actual paragraph append, and confirmation that the keyboard hides
  and the paragraph becomes visible.
- Unsaved changes: automated navigation tests cover Cancel/Stay
  and explicitly discarding when leaving the editor.
- All four editor warnings: collapsed by default; tap opens
  a scrollable and bounded modal with a clear close control.
  Android PPTX sheet opening, scrolling and closing were verified
  after an inline ExpansionTile caused a genuine 24 px overflow.
- Maintain >=48 dp primary touch targets and avoid using warnings
  or marketing banners that push the editing canvas below the fold.
- Physical ARM64 smartphone, landscape and other text scaling/device
  combinations still require additional testing.
