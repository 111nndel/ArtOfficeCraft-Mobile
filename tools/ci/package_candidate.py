"""Verify an ordinary offline APK and prepare data for the isolated signing job."""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_android_apk import verify


def main():
    apk = Path('build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk')
    report = verify(apk)
    sdk = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
    permissions = subprocess.check_output([str(sdk / 'aapt'), 'dump', 'permissions', str(apk)], text=True)
    if re.search(r'android\.permission\.(INTERNET|ACCESS_WIFI_STATE|CHANGE_WIFI_STATE)', permissions):
        raise ValueError('Offline permission policy failed')
    subprocess.run([str(sdk / 'zipalign'), '-c', '-P', '16', '4', str(apk)], check=True)
    subprocess.run([str(sdk / 'apksigner'), 'verify', str(apk)], check=True)
    identity = subprocess.check_output([str(sdk / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    version = re.search(r'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$', Path('pubspec.yaml').read_text(), re.M)
    if version is None:
        raise ValueError('Unsupported pubspec version')
    name, base = version.groups()
    if f"name='ai.artofficecraft.artofficecraft_mobile'" not in identity or f"versionName='{name}'" not in identity or f"versionCode='{2000 + int(base)}'" not in identity:
        raise ValueError('Unexpected Android application identity')
    tag = os.environ.get('RELEASE_TAG', '')
    if tag and not re.fullmatch(r'v' + re.escape(name) + r'-alpha\.[0-9]+', tag):
        raise ValueError('Release tag must match the application version')
    dest = Path('build/apk-candidate')
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(apk, dest / apk.name)
    shutil.copy2('assets/legal/rust-licenses.json', dest / 'rust-licenses.json')
    pins = json.loads(Path('upstream/engines.lock.json').read_text())
    metadata = dict(sourceCommit=os.environ['GITHUB_SHA'], version=name,
                    versionCode=2000 + int(base), workflowRun=os.environ['GITHUB_RUN_ID'],
                    sha256BeforeSigning=hashlib.sha256(apk.read_bytes()).hexdigest(),
                    engines=pins['engines'], checks=report, offlinePermissionsVerified=True,
                    flutter='3.47.9', dart='3.13.7', rust='1.99.1', ndk='28.2.13676358')
    (dest / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (dest / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    (dest / 'permissions.txt').write_text(permissions)
    notes = Path('docs') / f'release-{name}-alpha.1.md'
    (dest / 'release-notes.md').write_text(
        (notes.read_text(encoding='utf-8') if notes.is_file() else f'ArtOfficeCraft Mobile {name} development preview.\n')
        + '\n\nBuilt on GitHub Actions. Flutter unit/widget tests, Rust tests and APK package checks passed. '
        'This workflow does not run Android emulator tests. The existing development signing certificate is used.\n'
        + f'\nSource: {os.environ["GITHUB_SHA"]}\n'
        + f'\nBuild: https://github.com/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{os.environ["GITHUB_RUN_ID"]}\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
