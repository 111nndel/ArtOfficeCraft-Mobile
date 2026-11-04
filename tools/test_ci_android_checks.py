import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location(
    'android_checks', Path(__file__).parent / 'ci/run_android_checks.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)


class AndroidChecksTests(unittest.TestCase):
    def test_manifest_is_restored_byte_for_byte_when_a_suite_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / 'android/app/src/debug/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            original = b'<manifest><!-- offline -->\r\n</manifest>\r\n'
            manifest.write_bytes(original)
            with self.assertRaisesRegex(RuntimeError, 'test failure'):
                with qa.test_manifest(manifest):
                    self.assertIn('android.permission.INTERNET', manifest.read_text())
                    raise RuntimeError('test failure')
            self.assertEqual(manifest.read_bytes(), original)

    def test_failed_suite_stops_before_building_or_installing_ordinary_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / 'android/app/src/debug/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest/>')
            logcat = MagicMock()
            with patch.object(qa, 'ROOT', root), \
                    patch.dict(os.environ, {'ANDROID_HOME': tmp, 'GITHUB_STEP_SUMMARY': ''}), \
                    patch.object(qa, 'capture', side_effect=['36', 'x86_64']), \
                    patch.object(qa.subprocess, 'Popen', return_value=logcat), \
                    patch.object(qa, 'run', side_effect=RuntimeError('native edit failed')) as run:
                with self.assertRaisesRegex(RuntimeError, 'native edit failed'):
                    qa.checks('emulator-5554', root / 'proof')
            self.assertEqual(run.call_count, 1)
            self.assertEqual(manifest.read_text(), '<manifest/>')
            report = json.loads((root / 'proof/summary.json').read_text())
            self.assertFalse(report['passed'])
            self.assertEqual(report['suites'], [])
            self.assertIn('native edit failed', report['error'])
            logcat.terminate.assert_called_once()

    def test_bad_permissions_and_fake_images_cannot_be_reported_as_verified(self):
        for name in ['INTERNET', 'ACCESS_WIFI_STATE', 'ACCESS_NETWORK_STATE']:
            with self.assertRaises(RuntimeError):
                qa.verify_offline(f"uses-permission: name='android.permission.{name}'")
        qa.verify_offline("uses-permission: name='app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'")
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            with self.assertRaises(RuntimeError):
                qa.screenshot_names(directory)
            (directory / 'capture.png').write_text('run-as: permission denied')
            with self.assertRaises(RuntimeError):
                qa.screenshot_names(directory)

    def test_physical_devices_are_rejected_before_any_process_is_started(self):
        with patch.object(qa, 'capture') as capture:
            with self.assertRaises(ValueError):
                qa.checks('physical-phone', Path('unused'))
            capture.assert_not_called()


if __name__ == '__main__':
    unittest.main()
