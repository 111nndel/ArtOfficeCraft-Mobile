# PDF renderer fidelity harness

The harness exercises the application C ABI on Linux and the existing Dart worker
and FFI on an API 36 x86_64 Android emulator. Native evidence deliberately has no
OS fallback. Android PdfRenderer renders the identical generated fixture as a
separate baseline. Poppler is the independent reference; all three candidates use
the same fixed numerical policy in `compare.py`.

Eight original pages cover embedded Cyrillic TTF styles, JPEG, RGBA/PDF alpha,
vector clipping, rotation, offset CropBox, original Type3 vector glyphs and
AcroForm text/checkbox appearances. Type3 geometry is original; embedded DejaVu
subsets retain their Bitstream-Vera notice. No personal or third-party sample
PDFs are used. These cases are regression evidence, not universal PDF fidelity.
CFF fonts, complex ICC/spot colour and arbitrary real documents need more testing.

Page mean error must be <=8/255, with <=5% of pixels differing by >32 in any
channel. Each content region must have mean error <=12/255, severe differences
<=15%, ink ratio 0.75..1.45 and at least 100 dark reference pixels. Missing pages,
wrong dimensions and empty/invalid regions fail. Metrics never resize images.

```sh
python -m pip install -r tools/pdf_fidelity/requirements.txt
bash tools/pdf_fidelity/run.sh
```

Requires Linux, Rust 1.99.1, Poppler and DejaVu fonts. Results are under
`build/pdf-renderer-fidelity/results/`: fixture provenance/notices, actual PNGs,
comparison JSON, amplified differences, review pairs and Linux process memory.
The Python ctypes consumer uses `ac_pdf_render` and `ac_result_free`; there is no
second test-only renderer implementation or modification of staged engine code.

Android builds the real x86_64 core from the same pinned sources and dependency
lock. Fixture assets and the local driver network permission exist only in the
isolated debug build; the runner restores both pubspec and manifest on exit.
The driver bounds PNG transfers and separates `android` from `rust-android`
evidence. `comparison-rust-android.json` proves native output rather than silently
accepting the OS fallback. Python/reference tools are development dependencies,
not shipped application dependencies. The signed app remains offline.
