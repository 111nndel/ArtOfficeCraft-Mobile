# ArtOfficeCraft Mobile 0.43.0

> Android ARM64 development preview.

## What's New

- PDF and presentation reading modes now save through the same ordered Dart file store on all native targets.
- Android retains read-only compatibility with old preferences. Existing modes remain readable after an update; new choices take precedence in private JSON files.
- Separate storage adapter instances share write ordering. A failed write preserves the last saved mode and does not block later saves.
- Removes the Kotlin reading-preference writer. No runtime package, online service, engine update or new interface setting is added.
- Native core 0.42.0 and all four engine source pins are unchanged.

## Known Limitations

- Android remains the only packaged application target. Shared storage and Rust rendering do not establish a complete desktop or iOS app.
- Legacy Android preferences remain available for upgrade compatibility. They are not deleted or rewritten.
- Office/PDF document fidelity and editing capabilities are unchanged.
- Runtime checks use an Android 16 x86_64 emulator. Physical-device validation of this version is separate.
