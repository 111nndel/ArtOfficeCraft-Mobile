# Android editor checks on GitHub Actions

The `Android 16 emulator and editor scenarios` job runs on a GitHub-hosted
Ubuntu 24.04 machine. It does not need a contributor's PC, a self-hosted runner,
an attached phone, or the preview signing key. It runs on the same push/PR/manual
events as the existing workflow. Future tagged publication requires both the
ordinary ARM64 package job and this emulator job to succeed.

The job stages the four exact upstream source pins, runs native tests and compiles
the Rust core for x86_64 with 16-KiB ELF alignment. Flutter/Java/NDK match the
ordinary build. A pinned emulator-runner action starts an API 36 Google APIs
x86_64 image with the Pixel 7 hardware profile and KVM acceleration.

`tools/ci/run_android_checks.py` drives all four integration suites:

| Suite | Current scenarios | Coverage |
| --- | ---: | --- |
| native_editors | 9 | Four real engines, in-page editing/export, recovery, English UI, worker/media lifetime, distant cells, imported layout, resizing, formulas and zoom |
| office_features | 6 | Word replacement, active/new sheets, PPTX order and pictures, PDF rotation and order, touch reading modes and saved PDF mode |
| range_features | 6 | Touch range selection/format/clear, sort direction and header, worksheet filtering by value and blanks, whole rows and columns, cross-sheet formulas, undo/redo, Word color/indent/spacing, export and reopen |
| clipboard_features | 3 | Real Android clipboard identity, cross-workbook/sheet style and formula paste, special modes, external Unicode TSV, export and undo |

Flutter's host-side integration driver saves the existing screenshots directly
under `build/android-qa/screenshots`. A screenshot must contain a PNG signature;
a missing/invalid screenshot or failing suite fails the job. Screenshots are
evidence for inspection, not automatic pixel-perfect golden comparisons.
The driver avoids the race in which the test app is uninstalled before a host
can copy app-private screenshot files.

Only the test debug manifest temporarily receives INTERNET for the Flutter VM
service. It is restored byte-for-byte on normal completion or a Python exception,
including command timeouts. The job then explicitly rebuilds `lib/main.dart` as an
ordinary profile application. Its network permissions, bundled notices, native
16-KiB alignment, ZIP alignment and signature must pass. The two existing ADB
scripts then exercise real DocumentsUI filters/imports, held-finger resizing,
undo and two sequential recent imports followed by force-stop/reopen.

The `android-16-qa` artifact retains logs, logcat, screenshots, permission/package
reports and `summary.json` for seven days, including partial evidence on failure.
Test/QA APKs are excluded from that upload. The separate publication job consumes
only the ordinary ARM64 candidate, holds the signing secret and verifies the
existing certificate. Emulator tests do not gain signing credentials.

The default image does not prove operation on a device using actual 16-KiB memory
pages, and a virtual Pixel does not replace testing on a physical Vivo. Complex
Office fidelity and visual quality still need human review of the captured images
and representative files. The ordinary APK remains offline. Clipboard text and an opaque token use the
Android clipboard; the rich source snapshot stays only in process memory.

On a disposable Linux Android 16 x86_64 emulator, the runner can also be reproduced
with `python3 tools/ci/run_android_checks.py --device emulator-5554` after installing
the pinned tools, compiling/copying the matching core and running `flutter pub get`.
The script rejects physical-device serials. A failed suite stops before ordinary
app checks and cannot satisfy the publication dependency.

References: [emulator runner source](https://github.com/ReactiveCircus/android-emulator-runner/tree/a421e43855164a8197daf9d8d40fe71c6996bb0d)
and [Flutter integration screenshot driver](https://github.com/flutter/flutter/blob/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/integration_test/lib/integration_test_driver_extended.dart).
