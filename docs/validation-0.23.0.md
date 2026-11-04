# ArtOfficeCraft Mobile 0.23.0 validation

## Behavior and data boundaries

Grid selection is one inclusive rectangle. Long-press enters selection; two 44-dp
hit targets resize it with document-space hit testing. A held handle near a view
edge scrolls the sheet without changing zoom. Releasing/cancelling/disposal stops
the timer. Pinch and pan retain the range. An address pane accepts reversed and
absolute A1 endpoints, validates Excel bounds and expands intersecting merges.
A range is limited to 4096 cells, including merge expansion. Ordinary editable
10–500% sheet navigation and empty surrounding cells remain unchanged.

Formatting and clearing use additive actions on the existing XLSX C ABI. The
adapter checks bounds, protection and whole-merge selection before editing.
Formatting addresses each distinct merge anchor once. Clearing resets value,
formula and Python expression at every coordinate, preserving its style. It
recalculates formulas once after clearing. Output must pass the existing native
inspection before bytes/history are installed. Existing undo/redo, working-copy
and recovery paths apply. Pending input is flushed before a range action, as a
separate preceding edit; a failed range action leaves that committed input intact.
A regular single-cell formatting action still commits pending value and style in
one transaction. No clipboard implementation or new native dependency was added.

Word adds selected foreground RGB and automatic color through the existing UTF-16
character-range patch. Preview now supplies explicit RGB and paragraph multiple
line spacing. Both inline input and static text use the same run-color styles and
line-height multiplier. Left paragraph indent is displayed in document pixels;
the tool offers 0/12/24/36 pt. Exact/minimum line-spacing modes, negative/hanging
indentation and inherited/theme color resolution are not implemented in this view.

## Verification

- Clean Flutter analysis; 128 unit/widget tests passed, including range bounds,
  chained merges, grow/shrink handles, edge auto-scroll and stop-on-release,
  pinch preservation, large text/320-dp range controls, atomic failed clear,
  outside-cell retention, clear-preserves-style, undo/redo and inline run colors.
- 33 Rust tests passed. New exported/reopened XLSX checks cover range styles,
  formula preservation/recalculation, merge/protection/size rejection; DOCX checks
  UTF-16 emoji color, automatic color, indent and multiple line spacing.
- 11 Python updater/license tests passed.
- Android 16 API 36 x86_64: nine existing real-engine scenarios plus the four
  0.22 feature scenarios passed. The two new 0.23 scenarios passed: finger
  long-press/drag and exact range entry, bulk bold/clear, recalculation, undo/redo,
  Save As/reopen with original bytes retained; Word emoji-range color, displayed
  spacing/indent and saved/reopened DOCX agreement. Integration Save As uses a
  mocked dialog. The 13 earlier scenarios retain worker/media lifecycle, recovery,
  English UI, zoom, imported/distant cell editing, resize, sheet creation, Word
  replacement, PPTX order/pictures and PDF rotation/order coverage.
- Ordinary profile APK explicitly rebuilt from lib/main.dart: package/ZIP/native
  16-KB alignment, license notices and certificate checks passed. Its permissions
  contain no INTERNET or network-state permissions. The preview certificate is
  unchanged. Actual system-picker/recent-document checks are recorded below.

## Limits

The physical Vivo Android 16 and a runtime with actual 16-KB pages are unavailable.
Window reads and edits still reparse whole documents. Complex Office round-trip
fidelity and full page layout remain incomplete. This release focuses on Excel
and Word; Deck/PDF behavior and four engine pins are unchanged from 0.22. See the
previous validation for their supported operations. Exports remain separate copies.
