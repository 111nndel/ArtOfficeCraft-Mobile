"""Disposable HTTPS fixture for the emulator updater test; never a public source."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import ssl


def serve(root, evidence, certificate, key):
    fixture = json.loads((root / 'fixture.json').read_text())
    prefix = 'https://github.com/111nndel/ArtOfficeCraft-Mobile/releases/download/'
    version = fixture['nextVersion']
    tag = f'v{version}-alpha.1'
    name = f'ArtOfficeCraft-Mobile-{version}-arm64-preview.apk'
    identities = {name: (root / name).stat().st_size for name in ('valid.apk', 'wrong-key.apk', 'old.apk')}
    digests = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identities}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path == '/health':
                self.send_json({'ready': True})
                return
            mode = (evidence / 'mode.txt').read_text().strip()
            with (evidence / 'requests.jsonl').open('a') as stream:
                stream.write(json.dumps({'path': self.path, 'mode': mode}) + '\n')
            selected = {'wrong-key': 'wrong-key.apk', 'old-code': 'old.apk'}.get(mode, 'valid.apk')
            size, digest = identities[selected], digests[selected]
            if self.path.startswith('/repos/111nndel/ArtOfficeCraft-Mobile/releases?'):
                assets = [{'name': 'build-info.json', 'browser_download_url': f'{prefix}{tag}/build-info.json'},
                          {'name': name, 'browser_download_url': f'{prefix}{tag}/{name}', 'size': size, 'digest': 'sha256:' + digest}]
                self.send_json([{'draft': False, 'prerelease': True, 'tag_name': tag, 'assets': assets}])
            elif self.path.endswith('/build-info.json'):
                self.send_json({'tag': tag, 'version': version, 'versionCode': fixture['nextCode'],
                                'apk': name, 'sha256': digest,
                                'signingCertificateSha256': '4e16cc21d19cdcde840361cd34fbdcfbf901b48c6f8ff66ef473e7ddf4a05005'})
            elif self.path.endswith('/' + name):
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.android.package-archive')
                self.send_header('Content-Length', str(size))
                self.end_headers()
                try:
                    with (root / selected).open('rb') as stream:
                        first = True
                        while chunk := stream.read(65536):
                            if first and mode == 'corrupt':
                                chunk = bytes([chunk[0] ^ 1]) + chunk[1:]
                            first = False
                            self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    pass
            else:
                self.send_error(404)

        def send_json(self, value):
            data = json.dumps(value).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(('127.0.0.1', 8765), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('certificate')
    parser.add_argument('key')
    args = parser.parse_args()
    serve(args.root, args.evidence, args.certificate, args.key)
