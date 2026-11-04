"""Run real-engine Android scenarios, then verify an ordinary offline APK.

For a disposable API 36+ x86_64 emulator only. The test VM needs INTERNET;
the original debug manifest is restored before building the ordinary app.
Never upload or distribute the integration APK as a preview.
"""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SUITES = ('native_editors', 'office_features', 'range_features')
PNG = b'\x89PNG\r\n\x1a\n'


@contextmanager
def test_manifest(path):
    original = path.read_bytes()
    try:
        path.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                        '<uses-permission android:name="android.permission.INTERNET"/>'
                        '</manifest>\n')
        yield
    finally:
        path.write_bytes(original)


def run(command, log, *, env=None, timeout=900):
    """Log the process tree and stop it on timeout, including Flutter children."""
    print('Running: ' + ' '.join(map(str, command)), flush=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('wb') as stream:
        process = subprocess.Popen(list(map(str, command)), cwd=ROOT,
                                   env=env, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise RuntimeError(f'Timed out; see {log}') from None
    if code:
        # Keep failure details visible in the Actions log as well as the artifact.
        print(log.read_text(errors='replace')[-20000:], flush=True)
        raise RuntimeError(f'Command exited {code}; see {log}')


def capture(command, *, timeout=30):
    return subprocess.check_output(list(map(str, command)), cwd=ROOT,
                                   text=True, timeout=timeout).strip()


def screenshot_names(directory):
    paths = sorted(directory.glob('*.png'))
    if not paths or any(not p.read_bytes().startswith(PNG) for p in paths):
        raise RuntimeError(f'Missing or invalid screenshots in {directory}')
    return [p.name for p in paths]


def verify_offline(permissions):
    if re.search(r'android\.permission\.(INTERNET|ACCESS_NETWORK_STATE|'
                 r'ACCESS_WIFI_STATE|CHANGE_WIFI_STATE)\b', permissions):
        raise RuntimeError('Ordinary APK unexpectedly requests network access')


def checks(device, output):
    if not re.fullmatch(r'emulator-\d+', device):
        raise ValueError('Use a disposable emulator, not a physical device')
    sdk = Path(os.environ['ANDROID_HOME'])
    adb = [str(sdk / 'platform-tools/adb'), '-s', device]
    api = int(capture([*adb, 'shell', 'getprop', 'ro.build.version.sdk']))
    abi = capture([*adb, 'shell', 'getprop', 'ro.product.cpu.abi'])
    if api < 36 or abi != 'x86_64':
        raise ValueError('Use Android 16+ x86_64 with the matching native library')
    output.mkdir(parents=True, exist_ok=True)
    report = {'device': device, 'api': api, 'abi': abi, 'passed': False,
              'source': os.environ.get('GITHUB_SHA'), 'suites': []}
    logcat = None
    log_stream = None
    try:
        log_stream = (output / 'logcat.txt').open('wb')
        logcat = subprocess.Popen([*adb, 'logcat', '-v', 'threadtime'],
                                 stdout=log_stream,
                                 stderr=subprocess.STDOUT)
        manifest = ROOT / 'android/app/src/debug/AndroidManifest.xml'
        with test_manifest(manifest):
            for suite in SUITES:
                start = time.monotonic()
                directory = output / 'screenshots' / suite
                env = {**os.environ, 'AOC_SCREENSHOTS': str(directory)}
                run(['flutter', 'drive', '--debug', '--no-pub', '--disable-dds',
                     '--driver=test_driver/ci_integration.dart',
                     f'--target=integration_test/{suite}_test.dart', '-d', device],
                    output / f'{suite}.log', env=env)
                report['suites'].append({'name': suite, 'passed': True,
                                        'seconds': round(time.monotonic() - start, 1),
                                        'screenshots': screenshot_names(directory)})
        # Rebuild from the real application after manifest restoration. This
        # ordinary APK is used only for QA, not for signed release publication.
        run(['flutter', 'build', 'apk', '--profile', '--target=lib/main.dart',
             '--target-platform=android-x64', '--split-per-abi', '--no-pub'],
            output / 'ordinary-build.log')
        apk = ROOT / 'build/app/outputs/flutter-apk/app-x86_64-profile.apk'
        run([sys.executable, 'tools/verify_android_apk.py', apk],
            output / 'package-verification.json')
        build_tools = sdk / 'build-tools/36.0.0'
        permissions = capture([build_tools / 'aapt', 'dump', 'permissions', apk])
        (output / 'permissions.txt').write_text(permissions + '\n')
        verify_offline(permissions)
        run([build_tools / 'apksigner', 'verify', apk], output / 'signature.txt')
        run([build_tools / 'zipalign', '-c', '-P', '16', '4', apk],
            output / 'zipalign.txt')
        for script in ('test_grid_touch_import', 'test_recent_imports'):
            run(['node', f'tools/{script}.js', device, apk],
                output / f'{script}.log', timeout=420)
        report['ordinaryApp'] = {'offline': True, 'native16KiBAligned': True,
                                 'systemPickerAndTouchResize': True,
                                 'recentCopiesAfterForceStop': True}
        report['passed'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if logcat is not None:
            logcat.terminate()
            try:
                logcat.wait(timeout=10)
            except subprocess.TimeoutExpired:
                logcat.kill()
                logcat.wait()
        if log_stream is not None:
            log_stream.close()
        (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as stream:
                stream.write(f"### Android {api} emulator checks\n\n"
                             f"Result: **{'passed' if report['passed'] else 'failed'}**. "
                             f"Completed suites: {len(report['suites'])}/{len(SUITES)}. "
                             'Logs, screenshots and summary.json are in the Android QA artifact.\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='emulator-5554')
    args = parser.parse_args()
    checks(args.device, ROOT / 'build/android-qa')
