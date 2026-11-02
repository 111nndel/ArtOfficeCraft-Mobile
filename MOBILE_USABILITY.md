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
