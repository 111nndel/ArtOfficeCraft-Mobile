"""Exercise the application's real C ABI; no duplicate renderer consumer."""
import ctypes
import hashlib
import json
import sys
from pathlib import Path


class Result(ctypes.Structure):
    _fields_ = [('status', ctypes.c_int32), ('ptr', ctypes.c_void_p),
                ('length', ctypes.c_size_t), ('capacity', ctypes.c_size_t)]


def main(library, fixture, output):
    engine = ctypes.CDLL(str(Path(library).resolve()))
    engine.ac_pdf_render.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
    engine.ac_pdf_render.restype = Result
    engine.ac_result_free.argtypes = [Result]
    engine.ac_result_free.restype = None

    def call(data, request):
        payload = json.dumps(request).encode()
        result = engine.ac_pdf_render(data, len(data), payload, len(payload))
        try:
            if result.length > 24*1024*1024 or result.length > result.capacity or (result.length and not result.ptr):
                raise ValueError('Invalid native output allocation')
            value = ctypes.string_at(result.ptr, result.length)
            if result.status != 0:
                raise ValueError(value.decode(errors='replace'))
            return value
        finally:
            engine.ac_result_free(result)

    fixture, output = Path(fixture), Path(output)
    data = (fixture / 'fixture.pdf').read_bytes()
    manifest = json.loads((fixture / 'manifest.json').read_text())
    if len(data) > 64*1024*1024 or hashlib.sha256(data).hexdigest() != manifest['pdfSha256']:
        raise ValueError('Invalid fixture provenance')
    session = json.loads(call(data, {'op': 'open'}))
    if session['pageCount'] != len(manifest['pages']):
        raise ValueError('Unexpected page count')
    output.mkdir(parents=True, exist_ok=True)
    try:
        for page in manifest['pages']:
            number = page['page']
            png = call(b'', {'op': 'page', 'session': session['session'], 'page': number-1, 'width': page['size'][0]})
            if not png.startswith(b'\x89PNG\r\n\x1a\n'):
                raise ValueError('Non-PNG native result')
            (output / f'page-{number:02}.png').write_bytes(png)
            print(f'page={number} bytes={len(png)} warnings=0', flush=True)
    finally:
        call(b'', {'op': 'close', 'session': session['session']})


if __name__ == '__main__':
    main(*sys.argv[1:])
