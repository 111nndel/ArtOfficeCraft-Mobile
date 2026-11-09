#!/usr/bin/env bash
set -euo pipefail

results="$PWD/build/pdf-renderer-fidelity/results"
backup="${RUNNER_TEMP:?}/fidelity-pubspec.yaml"
cp pubspec.yaml "$backup"
trap 'cp "$backup" pubspec.yaml; rm -f assets/qa/pdf-fidelity.pdf assets/qa/pdf-fidelity.json assets/qa/pdf-fidelity-font-notice.txt' EXIT
mkdir -p assets/qa
cp "$results/fixture/fixture.pdf" assets/qa/pdf-fidelity.pdf
cp "$results/fixture/manifest.json" assets/qa/pdf-fidelity.json
cp "$results/fixture/FONT-NOTICE.txt" assets/qa/pdf-fidelity-font-notice.txt
python - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
source = p.read_text()
needle = '    - assets/legal/rust-licenses.json'
if source.count(needle) != 1:
    raise SystemExit('Unexpected asset declaration; refusing to patch pubspec')
p.write_text(source.replace(needle, needle + '\n    - assets/qa/pdf-fidelity.pdf\n    - assets/qa/pdf-fidelity.json\n    - assets/qa/pdf-fidelity-font-notice.txt'))
PY
{ adb shell getprop ro.build.version.sdk; adb shell getprop ro.product.cpu.abi; } \
  > "$results/android-environment.txt"
python - <<'PY'
from pathlib import Path
import sys

sys.path.insert(0, 'tools/ci')
from run_android_checks import run, test_manifest

# Only the disposable test build needs the local Flutter driver connection.
# Reuse the existing bounded runner and restore the offline manifest on exit.
with test_manifest(Path('android/app/src/debug/AndroidManifest.xml')):
    run(['flutter', 'drive', '--debug', '--disable-dds',
         '--target=integration_test/pdf_fidelity_test.dart',
         '--driver=test_driver/pdf_fidelity.dart', '-d', 'emulator-5554'],
        Path('build/pdf-renderer-fidelity/results/android-driver.txt'), timeout=600)
PY
python tools/pdf_fidelity/compare.py "$results" --candidate android
python tools/pdf_fidelity/compare.py "$results" --candidate rust-android
