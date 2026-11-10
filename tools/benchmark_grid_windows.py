#!/usr/bin/env python3
"""Compare the unchanged stateless ABI with owned reader windows. Stdlib only.

Timing is evidence, never a pass/fail threshold. Equality and native failures are
checked. Synthetic numeric XLSX, host release core; this is not Android UI FPS.
"""
import argparse
import ctypes
import io
import json
from pathlib import Path
import statistics
import time
import zipfile


class Result(ctypes.Structure):
    _fields_ = [('status', ctypes.c_int32), ('ptr', ctypes.c_void_p),
                ('length', ctypes.c_size_t), ('capacity', ctypes.c_size_t)]


def fixture(rows=10000, columns=10):
    ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    parts = {
        '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
        '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{rel}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        'xl/workbook.xml': f'<workbook xmlns="{ns}" xmlns:r="{rel}"><sheets>'
            '<sheet name="Benchmark" sheetId="1" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{rel}/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
        'xl/worksheets/sheet1.xml': f'<worksheet xmlns="{ns}"><sheetData>' + ''.join(
            f'<row r="{r+1}">' + ''.join(
                f'<c r="{chr(65+c)}{r+1}"><v>{r*columns+c}</v></c>'
                for c in range(columns)) + '</row>' for r in range(rows)) + '</sheetData></worksheet>',
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, content in parts.items():
            archive.writestr(name, content)
    return buffer.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    library = ctypes.CDLL(str(args.library.resolve()))
    inspect = library.ac_xlsx_inspect_window
    inspect.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
    inspect.restype = Result
    library.ac_result_free.argtypes = [Result]
    library.ac_result_free.restype = None

    def call(data, request):
        encoded = json.dumps(request).encode()
        result = inspect(data, len(data), encoded, len(encoded))
        try:
            output = ctypes.string_at(result.ptr, result.length)
            if result.status:
                raise RuntimeError(output.decode(errors='replace'))
            return json.loads(output)
        finally:
            library.ac_result_free(result)

    data = fixture()
    requests = [dict(sheet=0, row=i*397, column=0, rows=64, columns=10,
                     selected=f'A{i*397+1}') for i in range(24)]
    start = time.perf_counter()
    session = call(data, {'reader': 'open'})['session']
    cold_ms = (time.perf_counter() - start)*1000
    assert session is not None, 'No reader available in standalone benchmark'
    times = {'stateless': [], 'reader': []}
    try:
        for i, request in enumerate(requests):
            outputs = {}
            # Alternate ordering to reduce warmup/scheduling bias.
            for mode in (('stateless', 'reader') if i % 2 else ('reader', 'stateless')):
                start = time.perf_counter()
                outputs[mode] = call(data, request) if mode == 'stateless' else call(b'',
                    {'reader': 'view', 'session': session, 'view': request})
                times[mode].append((time.perf_counter() - start)*1000)
            assert outputs['reader'] == outputs['stateless'], 'Window result changed'
            assert outputs['reader']['selection']['input'] == str(request['row']*10)
    finally:
        call(b'', {'reader': 'close', 'session': session})
    report = {'scope': 'Synthetic 100000 numeric cells; host release C ABI plus Python JSON decoding; not Android UI FPS',
              'cells': 100000, 'windows': len(requests), 'equalOutputs': True,
              'coldReaderOpenMs': cold_ms,
              'medianMs': {mode: statistics.median(values) for mode, values in times.items()},
              'samplesMs': times}
    report['medianSpeedup'] = report['medianMs']['stateless']/report['medianMs']['reader']
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'samplesMs'}, indent=2))


if __name__ == '__main__':
    main()
