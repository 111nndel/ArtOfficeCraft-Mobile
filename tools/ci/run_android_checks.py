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
import shutil
import signal
import ssl
import subprocess
import sys
from tempfile import TemporaryDirectory
import time
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_android_apk import verify_release_manifest, verify_update_permissions

ROOT = Path(__file__).resolve().parents[2]
SUITES = ('native_editors', 'office_features', 'range_features', 'clipboard_features')
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


def update_checks(device, apks, private, key, build_tools, output):
    """Real app updater against HTTPS fixtures; QA signing keys never leave runner."""
    staging = ROOT / 'build/update-fixture'
    evidence = ROOT / 'build/app-update-qa'
    staging.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / 'mode.txt').write_text('valid')
    match = re.search(r'^version: ([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$',
                      (ROOT / 'pubspec.yaml').read_text(), re.M)
    major, minor, patch, number = map(int, match.groups())
    current_version = f'{major}.{minor}.{patch}'
    next_version = f'{major}.{minor + 1}.0'
    run(['flutter', 'build', 'apk', '--release', '--target=lib/main.dart',
         '--target-platform=android-x64', '--split-per-abi',
         f'--build-name={next_version}', f'--build-number={number + 1}'],
        output / 'update-future-build.log')
    unsigned = private / 'future-unsigned.apk'
    shutil.copy2(apks / 'app-x86_64-release.apk', unsigned)
    other_key = private / 'wrong-key.p12'
    run(['keytool', '-genkeypair', '-storetype', 'PKCS12', '-keystore', other_key,
         '-storepass', 'android', '-alias', 'qa', '-keyalg', 'RSA', '-keysize', '2048',
         '-validity', '2', '-dname', 'CN=Wrong Update QA'], output / 'update-wrong-key.log')
    for signing_key, filename in ((key, 'valid.apk'), (other_key, 'wrong-key.apk')):
        run([build_tools / 'apksigner', 'sign', '--ks', signing_key,
             '--ks-key-alias', 'qa', '--ks-pass', 'pass:android',
             '--out', staging / filename, unsigned], output / f'update-sign-{filename}.log')
    run(['flutter', 'build', 'apk', '--release', '--target=test_driver/update_qa_main.dart',
         '--target-platform=android-x64', '--split-per-abi',
         f'--build-name={current_version}', f'--build-number={number}'],
        output / 'update-qa-app-build.log')
    qa_app = staging / 'old.apk'
    run([build_tools / 'apksigner', 'sign', '--ks', key,
         '--ks-key-alias', 'qa', '--ks-pass', 'pass:android', '--out', qa_app,
         apks / 'app-x86_64-release.apk'], output / 'update-sign-qa-app.log')
    badging = capture([build_tools / 'aapt', 'dump', 'badging', staging / 'valid.apk'])
    next_code = int(re.search(r"versionCode='([0-9]+)'", badging)[1])
    fixture = {'currentVersion': current_version, 'nextVersion': next_version, 'nextCode': next_code}
    (staging / 'fixture.json').write_text(json.dumps(fixture))
    (evidence / 'fixture.json').write_text(json.dumps(fixture))
    certificate, tls_key = private / 'tls.crt', private / 'tls.key'
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
         '-keyout', tls_key, '-out', certificate, '-days', '1',
         '-subj', '/CN=aoc-update-fixture'], output / 'update-tls.log')
    with (output / 'update-server.log').open('wb') as stream:
        server = subprocess.Popen([sys.executable, 'tools/serve_update_fixture.py',
                                   str(staging), str(evidence), str(certificate), str(tls_key)],
                                  cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while True:
                try:
                    with urllib.request.urlopen('https://127.0.0.1:8765/health', timeout=1,
                                                context=ssl._create_unverified_context()) as response:
                        assert json.load(response)['ready']
                    break
                except Exception:
                    if time.monotonic() > deadline or server.poll() is not None:
                        raise RuntimeError('Update fixture server failed to start') from None
                    time.sleep(0.2)
            run(['node', 'tools/test_app_updates.js', device, qa_app, staging / 'fixture.json'],
                output / 'test_app_updates.log', timeout=900)
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


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
                if suite == 'office_features':
                    # Seed pre-Dart preferences in the disposable debug app,
                    # before Flutter reinstalls it with the next test target.
                    package = 'ai.artofficecraft.artofficecraft_mobile'
                    capture([*adb, 'install', '-r', ROOT / 'build/app/outputs/flutter-apk/app-debug.apk'])
                    capture([*adb, 'shell', 'am', 'force-stop', package])
                    capture([*adb, 'shell', 'run-as', package, 'mkdir', '-p', 'shared_prefs'])
                    capture([*adb, 'shell', 'run-as', package, 'rm', '-f',
                             'files/workspace/reading-pdf.json', 'files/workspace/reading-deck.json'])
                    with (output / 'legacy-reading-fixture.txt').open('wb') as stream:
                        subprocess.run([*adb, 'shell', '-T', 'run-as', package, 'tee',
                                        'shared_prefs/reading_modes.xml'],
                                       input=b'<?xml version="1.0" encoding="utf-8"?><map><string name="pdf">continuous</string><string name="deck">vertical</string></map>',
                                       stdout=stream, stderr=subprocess.STDOUT,
                                       timeout=30, check=True)
                directory = output / 'screenshots' / suite
                if directory.exists():
                    shutil.rmtree(directory)
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
        # Flutter drive may retain test app data, unlike flutter test. Start the
        # ordinary phase clean; the Node scenarios then test persistence within it.
        with (output / 'remove-integration-app.log').open('wb') as stream:
            subprocess.run([*adb, 'uninstall', 'ai.artofficecraft.artofficecraft_mobile'],
                           stdout=stream, stderr=subprocess.STDOUT,
                           timeout=30, check=False)
        # Let Flutter regenerate the plugin registrant for each build mode.
        # --no-pub would reuse the integration-test registrant in release mode.
        run(['flutter', 'build', 'apk', '--release', '--target=lib/main.dart',
             '--target-platform=android-x64', '--split-per-abi'],
            output / 'ordinary-build.log')
        apks = ROOT / 'build/app/outputs/flutter-apk'
        apk = apks / 'app-x86_64-release.apk'
        run([sys.executable, 'tools/verify_android_apk.py', apk],
            output / 'package-verification.json')
        build_tools = sdk / 'build-tools/36.0.0'
        permissions = capture([build_tools / 'aapt', 'dump', 'permissions', apk])
        (output / 'permissions.txt').write_text(permissions + '\n')
        verify_update_permissions(permissions)
        badging = capture([build_tools / 'aapt', 'dump', 'badging', apk])
        verify_release_manifest(badging)
        (output / 'badging.txt').write_text(badging + '\n')
        # Recreate the previous profile build identity with the same application
        # code. The old public ARM64 APK cannot run on this x86_64 test target.
        run(['flutter', 'build', 'apk', '--profile', '--target=lib/main.dart',
             '--target-platform=android-x64', '--split-per-abi',
             '--build-name=0.33.0', '--build-number=39'],
            output / 'upgrade-baseline-build.log')
        baseline = apks / 'app-x86_64-profile.apk'
        baseline_badging = capture([build_tools / 'aapt', 'dump', 'badging', baseline])
        if "versionName='0.33.0'" not in baseline_badging or 'application-debuggable' not in baseline_badging.splitlines():
            raise RuntimeError('Expected the 0.33.0 debuggable profile baseline')
        with TemporaryDirectory(prefix='aoc-android-qa-') as directory:
            private = Path(directory)
            key = private / 'qa.p12'
            run(['keytool', '-genkeypair', '-storetype', 'PKCS12', '-keystore', key,
                 '-storepass', 'android', '-alias', 'qa', '-keyalg', 'RSA',
                 '-keysize', '2048', '-validity', '2', '-dname', 'CN=Android QA'],
                output / 'qa-key.log')
            signed = private / 'release.apk'
            signed_baseline = private / 'profile.apk'
            for source, target in ((baseline, signed_baseline), (apk, signed)):
                run([build_tools / 'apksigner', 'sign', '--ks', key, '--ks-key-alias', 'qa',
                     '--ks-pass', 'pass:android', '--out', target, source],
                    output / f'qa-sign-{target.stem}.log')
            run([build_tools / 'apksigner', 'verify', signed], output / 'signature.txt')
            run([build_tools / 'zipalign', '-c', '-P', '16', '4', signed],
                output / 'zipalign.txt')
            run(['node', 'tools/test_recent_imports.js', device, signed_baseline, signed],
                output / 'test_recent_imports.log', timeout=600)
            print((ROOT / 'build/recents-021/result.json').read_text(), flush=True)
            run(['node', 'tools/test_grid_touch_import.js', device, signed],
                output / 'test_grid_touch_import.log', timeout=420)
            update_checks(device, apks, private, key, build_tools, output)
        report['ordinaryApp'] = {'documentsLocal': True, 'updatePermissionsVerified': True, 'native16KiBAligned': True,
                                 'nonDebuggable': True, 'profileToReleaseUpgrade': True,
                                 'systemPickerAndTouchResize': True, 'externalViewAndShare': True,
                                 'recentCopiesAfterForceStop': True, 'recentHistoryCleanup': True,
                                 'updateModesAndInstaller': True}
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
