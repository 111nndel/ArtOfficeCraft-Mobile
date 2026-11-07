# Local draft recovery — 0.14.0

The approved HTML v1.3 and editor tool-panel navigation are unchanged. This
release adds local checkpoints and a recovery section to Home.

## Behavior

- Word retains the active paragraph text and UTF-16 selection; Grid retains the
  sheet, address and pending input; Deck retains the pending text form and its
  operation; PDF retains changed document bytes and the selected page.
- Home opens a saved checkpoint with fresh editor instances. Explicit recovery
  deletion asks for confirmation and leaves source files and workspace copies.
- Immutable Office snapshots are written before an atomic JSON journal update.
  Typing reuses the base bytes rather than calling Rust for each keystroke.
  JSON encoding runs off the Flutter UI isolate. Writes debounce for 350 ms;
  lifecycle pause/close requests a flush. Queues, revision and epoch checks keep
  delayed failures and discarded updates from replacing newer checkpoints.
- A successful export retires its checkpoint. Canceled or failed Save As retains
  recovery. Explicit discard must remove the journal before leaving the editor;
  a removal failure keeps the editor open. Malformed records are preserved.
- New document creation in Word asks before replacing unsaved work. Restoring
  PDF page selection now works during initial loading as well as normal navigation.

## Validation

- Flutter analysis reports no issues; all 73 unit/widget tests pass. The added
  tests cover persistence across fresh stores, base reuse, incomplete writes,
  path validation, failure/retry, queued discard, pause flush and save cleanup.
  Widget checks cover Home deletion, recovery without native edits, canceled
  and successful export, and failed discard handling.
- Two integration scenarios pass on the dedicated Android 16 API 36 x86_64 AVD.
  The existing scenario exercises real Rust editing, roundtrips and native views
  for all four formats. The new scenario recreates stores and editor instances,
  checks unapplied Word/Grid/Deck input (including an emoji), and reopens a
  modified two-page PDF on its saved second page. Word/Grid base files are also
  inspected to establish that pending text is restored from the journal.
- Rust adapters, core 0.13.0 / ABI 1 and all upstream pins are unchanged. Their
  previously passing 17 Rust tests were not rerun for this Dart-only change.
- `tools/test_recovery_force_stop.js` passes on the ordinary offline x86_64
  profile APK, outside the Flutter test runner. It types
  `RECOVERY_FORCE_STOP_014`, waits for the durable-checkpoint status, uses Android
  `am force-stop` without orderly shutdown, relaunches, opens Home recovery and
  verifies the exact unapplied text. Explicit discard removes the recovery entry.
  Home and recovered text screenshots were visually checked. Test APK SHA-256:
  `6b9df34fa83a4227903a26ee7825e2d05e501fab57db73e668de82c386728314`.
- Final ARM64 split profile APK: 37,614,038 bytes, versionCode 2020 (base 20),
  versionName 0.14.0. SHA-256:
  `7060cda0b764b69edd748d28be69a0f1f7644e7e883990c20489f5424ce1e849`.
  ZIP integrity, ELF/ZIP 16-KiB alignment, signature and offline permission checks
  pass. The certificate matches 0.13.0 (SHA-256
  `4e16cc21d19cdcde840361cd34fbdcfbf901b48c6f8ff66ef473e7ddf4a05005`).
  The APK contains all 94 Rust dependency licence texts. A normalized source
  manifest matched all 112 build/test/source files on the build PC.

## Limits

Only the last successfully written checkpoint can be recovered. Instant process
termination before the debounce/flush may lose the newest input; this is not a
guarantee against sudden storage or power failure. Recovery does not restore undo
history. The draft snapshot limit is 64 MiB and the journal limit is 4 MiB; errors
remain visible and the editor still offers explicit Save As.

No physical Vivo test or runtime 16-KiB-page test was performed. Office rendering,
the 55 x 12 spreadsheet viewport and the other limits recorded for 0.13.0 remain.
