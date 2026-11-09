# Contributing to ArtOfficeCraft Mobile

You can fork **this repository**, improve the mobile app and open a pull request.
Forks of forks are welcome too. We keep our Flutter UI, Rust adapters and the exact
upstream engine revisions visible so another developer can reproduce the port.

## Start here

- Read [README](README.md) for the actual supported editing operations and limits.
- Download a tagged preview from [Releases](https://github.com/111nndel/ArtOfficeCraft-Mobile/releases).
  A development branch may contain changes that have not passed Android tests.
- Keep [the approved interaction contract](design/INTERACTION_SPEC.md): one
  expandable tool slab, caption-driven sections, nested forms in the same slab,
  and large touch targets. Document content must remain mounted while using tools.
- Keep UI translations in `lib/l10n/en.dart`. Translate labels at UI boundaries;
  never translate user document content, filenames, sheet names or native command IDs.
- For a bug, describe app version, Android version, device, steps, expected behavior
  and actual behavior. Prefer a minimal non-private sample document.

## Verify a change

Use Flutter with the Dart SDK constraint from `pubspec.yaml`, Android SDK/NDK,
Rust and Python. Windows build scripts are provided; see README for engine setup.

```powershell
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
```

For intermediate Dart-only work, push a `checks/**` branch to run the fast
Flutter/analyzer/updater workflow without building native Android libraries.
Pull requests and release tags still run the full Rust, Flutter, APK and Android
emulator gate. A successful fast run alone does not qualify an APK for release.

For native changes also run the Rust tests, verify all four pins with
`tools/sync_native_pins.py`, and review updated dependency notices. Exercise real
engine operations on an Android 16 QA emulator using `tools/test_android_editors.ps1`.
The integration test build temporarily enables VM-service networking; **rebuild the
ordinary offline APK afterwards**. Do not distribute that private test APK.

Document preservation, pending input, Save As cancellation, recovery, undo and
small-screen layout need relevant regression checks. Emulator results do not prove
physical-phone or complex Office-document fidelity.

## Relationship to ArtCraft

This is an independent Flutter Android app using WordCraft, GridCraft, DeckCraft
and PDFCraft from the ArtCraft organization. It is not the `storytold/artcraft`
AI image/video application and has no single upstream Git history. The four
engine sources and exact pins are listed in README and `upstream/engines.lock.json`.
Do not claim affiliation or endorsement. Keep LICENSE, THIRD_PARTY_NOTICES.md and
all upstream/dependency notices when distributing your work.

An engine fix can be proposed to its original repository separately. Do not
replace engine pins merely to make the mobile repository appear in a fork network.
