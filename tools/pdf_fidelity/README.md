# PDF renderer fidelity harness

Development-only consumer of the exact PDFCraft source in `upstream/engines.lock.json`.
No renderer or Python dependency is linked into the Android application.

The workflow installs Poppler and openly licensed DejaVu fonts, generates one
original six-page PDF, and renders it at two pixels per PDF point. It compares
the pinned Rust CPU renderer with Poppler at the original pixel dimensions.
Cases cover embedded Cyrillic TTF styles, JPEG, RGBA/PDF alpha, vector clipping,
page rotation and an offset CropBox.

`compare.py` contains the thresholds chosen before the first comparison:
page mean channel error <= 8/255 and at most 5% of pixels differing by >32 in any
channel; each named content region additionally requires mean error <=12/255,
large-difference fraction <=15%, and candidate/reference ink ratio 0.75-1.45.
Reference regions must contain at least 100 dark pixels. A page-size mismatch,
missing output or invalid/empty content region fails; rasters are never resized
for the numerical comparison. These are a small fixture's regression criteria,
not a standard or proof of universal PDF compatibility.

Run on Linux with Rust 1.99.1, Poppler and DejaVu fonts installed:

```sh
python -m pip install -r tools/pdf_fidelity/requirements.txt
bash tools/pdf_fidelity/run.sh
```

Results under `build/pdf-renderer-fidelity/results/` include the generated PDF,
font hashes and notices, unscaled PNG/PPM rasters, amplified differences, review
pairs, numerical comparison JSON, renderer warnings, memory and source pins.
The screenshot pairs are resized only for review; inspect original rasters for
small text. A matching hash or a low average alone does not establish correctness.

The build adds this repository's test consumer as an auto-discovered Cargo
example in the isolated staged checkout. It does not edit upstream `src/`,
change a lockfile or feed that checkout into application builds. Its SHA-256 is
recorded with the results. Fixture graphics and labels are original under MIT;
DejaVu subsets retain the Bitstream-Vera notice alongside the PDF.
