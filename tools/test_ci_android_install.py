import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.name == 'posix' and shutil.which('bash'), 'Hosted Linux SDK helper')
class AndroidInstallTests(unittest.TestCase):
    def test_corrupt_downloads_are_retried_and_failure_is_bounded(self):
        with tempfile.TemporaryDirectory(prefix='aoc-sdk-') as tmp:
            root = Path(tmp)
            sdk = root / 'sdk with spaces'
            manager = sdk / 'cmdline-tools/latest/bin/sdkmanager'
            manager.parent.mkdir(parents=True)
            manager.write_text('''#!/usr/bin/env bash
set -euo pipefail
file="$ANDROID_HOME/attempts"
n=0; if [[ -f "$file" ]]; then n=$(cat "$file"); fi
n=$((n+1)); echo "$n" > "$file"
test "$1" = --install; test "$2" = 'ndk;28.2.13676358'
if [[ "$n" -lt 3 || "${AOC_TEST_FAIL:-}" == always ]]; then
  mkdir -p "$ANDROID_HOME/.temp"; echo truncated > "$ANDROID_HOME/.temp/archive.zip"
  exit 1
fi
test ! -e "$ANDROID_HOME/.temp/archive.zip"
''')
            manager.chmod(0o700)
            shim = root / 'bin'
            shim.mkdir()
            (shim / 'sleep').write_text('#!/usr/bin/env bash\nexit 0\n')
            (shim / 'sleep').chmod(0o700)
            preserved = sdk / 'existing-component'
            preserved.write_text('keep')
            env = {**os.environ, 'ANDROID_HOME': str(sdk), 'GITHUB_ACTIONS': 'true',
                   'PATH': str(shim) + os.pathsep + os.environ['PATH']}
            script = Path(__file__).resolve().parent / 'ci/install_android.sh'
            result = subprocess.run(['bash', str(script), 'ndk;28.2.13676358'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((sdk / 'attempts').read_text().strip(), '3')
            self.assertEqual(preserved.read_text(), 'keep')
            (sdk / 'attempts').unlink()
            result = subprocess.run(['bash', str(script), 'ndk;28.2.13676358'],
                                    env={**env, 'AOC_TEST_FAIL': 'always'}, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((sdk / 'attempts').read_text().strip(), '3')
            self.assertEqual(preserved.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
