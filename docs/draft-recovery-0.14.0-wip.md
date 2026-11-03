# Draft recovery — 0.14.0 work in progress

Status: source implementation and new tests prepared; **not released**. The
last tested downloadable version is 0.13.0. The build device stopped responding
while the new validation was being started, so the current implementation must
not be described as tested or delivered in an APK.

The intended behavior is recovery of the last durably written checkpoint after
Android closes the process, without changing the approved editor navigation.

- Home offers locally recoverable documents. An explicit delete asks for
  confirmation and never deletes the source or workspace copy.
- Each session stores immutable Office bytes and an atomically replaced JSON
  journal. Typing reuses the base snapshot; a base is retired only after a new
  manifest commits. Incomplete temporary files do not replace a durable record.
- Word retains active paragraph text and UTF-16 selection; Grid retains sheet,
  address and unapplied input; Deck retains the pending text request and form;
  PDF retains changed document bytes and the selected page.
- Debounced writes run without Rust calls per keystroke, and lifecycle pauses
  request an immediate flush. JSON encoding is moved off the Flutter UI isolate.
  Revision and epoch checks prevent stale failures or discard races from
  reintroducing older checkpoints.
- Successful export retires the recovery record; canceled/failed Save As retains
  it. Explicit editor discard must remove the record before allowing navigation;
  a removal failure keeps the editor open. Corrupt records are preserved.
- New document creation in Word now asks before replacing unsaved work, matching
  the other editors' existing replacement guards.

New test sources cover persistence across a fresh store, base reuse, incomplete
writes, invalid paths, delayed failures, queued update/discard ordering, pause
flush, save cleanup, editor restore without native edits, Home deletion and
failed discard handling. These added tests have not yet run on the final source.

Before release: run formatting/analyzer and the full Flutter suite; exercise
recovery with real Rust backends; force-stop and relaunch the ordinary Android 16
app while text remains unapplied; verify export/discard and the recovery UI;
build ARM64, inspect permissions/signature/alignment, then publish a new preview.
The signing/build machine must be reachable to produce an update compatible with
the existing APK certificate.

Limits to disclose: only a successfully written checkpoint can be recovered;
instant termination before the debounce/flush may lose the most recent input.
Recovery does not restore session-local undo history. Normal editor/rendering
limits remain. Rust engines and their pinned source revisions are unchanged.
