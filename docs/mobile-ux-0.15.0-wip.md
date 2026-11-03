# English UI and document gestures — 0.15.0 work in progress

**Not released. The latest validated APK remains 0.14.0-alpha.1.**

Implemented source changes:

- English and Russian UI with Android system-language selection and an app-private
  persisted override in About. Flutter Material controls use matching locales.
  UI translation is separate from document content, filenames, user-defined sheet
  names and native operation IDs. English template seeds are applied only when
  creating new sample documents. Existing documents are not translated.
- Sheet pinch zoom (50–300%), one-finger pan, viewport-based row construction and
  a visible column header. Formula input and tool touch targets keep their size.
  Zoom presets are connected inside the existing View / Zoom pane. Opening a new
  workbook resets its viewport. The 55 x 12 document preview limit is unchanged.
- PDF canvas fills the available editor area and starts at page width, instead of
  shrinking a complete page into the remaining screen height. Pan/pinch operate
  on the whole viewport. Thumbnails are initially hidden and explicitly toggled;
  fit-width / fit-page commands stay in Read / Zoom. Rotation swaps page dimensions.
- The approved expandable tool slab/navigation remains in place. Rust adapters,
  upstream engine revisions and the offline permission policy are unchanged.
- English contribution guidance explains how to fork this mobile repository and
  keep provenance, licenses and the UI contract.

Validation status: the first formatter/analyzer run completed and identified one
accidental parameter placement plus async-context/style issues. Those issues were
corrected in source. Six new regression tests were prepared for gestures, PDF
sizing, language persistence, English UI and preservation of user-authored data.
A third Android integration scenario was also prepared for English UI, native
document-text preservation, pending-input pinch zoom and full-width PDF.
The build PC stopped responding during the next validation request; its last
reported contact became stale despite the device being labelled Online.

The updated analyzer, full tests, real Android gesture/UI checks, screenshots and
ARM64 build have **not been confirmed**. No new APK or release was published.
Do not treat these source changes as validated before completing those checks.
Resynchronize the final GitHub source to the build PC before resuming; the final
source includes changes made after its last confirmed analyzer run.
Raw low-level engine diagnostics may still use their original language. Saved
language/viewport behavior on physical Vivo hardware is unverified.
