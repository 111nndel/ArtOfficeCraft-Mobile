"""Verify ZIP integrity, 16-KiB native alignment and bundled Rust notices.

Use aapt separately for the final merged Android permission manifest.
"""
import argparse
import json
import struct
import zipfile
from pathlib import Path


def verify(path):
    libraries = []
    with zipfile.ZipFile(path) as apk, open(path, 'rb') as raw:
        if apk.testzip() is not None:
            raise ValueError('Corrupt APK ZIP entry')
        notices = json.loads(apk.read('assets/flutter_assets/assets/legal/rust-licenses.json'))
        if not notices or any(not item.get('texts') for item in notices):
            raise ValueError('Missing Rust license texts')
        for entry in apk.infolist():
            if not entry.filename.startswith('lib/') or not entry.filename.endswith('.so'):
                continue
            data = apk.read(entry)
            if data[:5] != b'\x7fELF\x02' or data[5] != 1:
                raise ValueError('Expected a 64-bit little-endian ELF: ' + entry.filename)
            phoff = struct.unpack_from('<Q', data, 32)[0]
            phsize, count = struct.unpack_from('<HH', data, 54)
            loads = []
            for i in range(count):
                offset = phoff + i * phsize
                if struct.unpack_from('<I', data, offset)[0] == 1:
                    fileoff, address = struct.unpack_from('<QQ', data, offset + 8)
                    align = struct.unpack_from('<Q', data, offset + 48)[0]
                    if align < 16384 or (address - fileoff) % 16384:
                        raise ValueError('ELF LOAD incompatible with 16 KiB: ' + entry.filename)
                    loads.append(align)
            if not loads:
                raise ValueError('No ELF LOAD segments: ' + entry.filename)
            raw.seek(entry.header_offset + 26)
            name_size, extra_size = struct.unpack('<HH', raw.read(4))
            data_offset = entry.header_offset + 30 + name_size + extra_size
            if entry.compress_type == zipfile.ZIP_STORED and data_offset % 16384:
                raise ValueError('Uncompressed library not ZIP aligned to 16 KiB: ' + entry.filename)
            libraries.append({'path': entry.filename, 'loadAlignments': loads,
                              'compressed': entry.compress_type != zipfile.ZIP_STORED})
    if not any(item['path'].endswith('/libartoffice_core.so') for item in libraries):
        raise ValueError('ArtOfficeCraft Rust core missing')
    return {'zipIntegrity': True, 'native16KiBAlignment': True,
            'rustLicensePackages': len(notices), 'libraries': libraries}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk), indent=2))
