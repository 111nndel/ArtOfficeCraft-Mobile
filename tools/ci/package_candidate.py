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
from stage_pdf_ocr import verify_apk as verify_pdf_ocr


def release_tag(ref, version):
    if ref.startswith('refs/tags/'):
        tag = ref.removeprefix('refs/tags/')
    elif ref.startswith('refs/heads/codex/release-'):
        tag = ref.removeprefix('refs/heads/codex/release-')
    else:
        return ''
    if not re.fullmatch('v' + re.escape(version) + r'-alpha\.[0-9]+', tag):
        raise ValueError('Release ref must match the application version')
    return tag


def main():
    apk = Path('build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk')
    report = verify(apk)
    verify_pdf_ocr(apk)
    report['pdfOcrAssetsVerified'] = True
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
    tag = release_tag(os.environ.get('GITHUB_REF', ''), name)
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
    # Use the exact alpha tag first, then the canonical version notes.
    # Reject non-English notes instead of publishing inconsistent release text.
    from rewrite_release_metadata import notes_for
    current_tag = tag or f'v{name}-alpha.1'
    notes = notes_for(current_tag)
    apk_name = f'ArtOfficeCraft-Mobile-{name}-arm64-preview.apk'
    preview_url = (f'https://github.com/{os.environ["GITHUB_REPOSITORY"]}'
                   f'/releases/download/{current_tag}/{apk_name}')
    download = ('## Download\n\n'
                f'- [Android ARM64 preview APK]({preview_url})\n'
                '- Development preview; check the release assets for SHA-256 checksums.\n\n')
    notes = notes.replace('## Known Limitations', download + '## Known Limitations', 1)
    notes += ('\n\n## Build & Verification\n\n'
              '- Flutter unit/widget tests, Rust tests and APK package checks passed.\n'
              '- Publication requires Android 16 emulator and ordinary-app checks in the same run; '
              'this build alone does not prove complete editor fidelity.\n'
              '- The existing development preview signing certificate is used.\n'
              f'- Source commit: `{os.environ["GITHUB_SHA"]}`.\n'
              f'- [GitHub Actions build logs](https://github.com/{os.environ["GITHUB_REPOSITORY"]}'
              f'/actions/runs/{os.environ["GITHUB_RUN_ID"]}).\n')
    (dest / 'release-notes.md').write_text(notes, encoding='utf-8')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
