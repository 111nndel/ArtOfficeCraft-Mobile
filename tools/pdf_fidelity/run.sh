#!/usr/bin/env bash
set -euo pipefail

task_root="$PWD/build/pdf-renderer-fidelity"
results="$task_root/results"
mkdir -p "$results/reference" "$results/rust"
python -m unittest discover -s tools/pdf_fidelity -p '*_test.py' -v
python tools/pdf_fidelity/make_fixture.py "$results/fixture"
pdftoppm -r 144 -cropbox -png "$results/fixture/fixture.pdf" "$results/reference/page"
pdfinfo "$results/fixture/fixture.pdf" > "$results/pdfinfo.txt"
pdftoppm -v 2> "$results/reference-version.txt"
rustup toolchain install 1.99.1 --profile minimal
rustup override set 1.99.1
python tools/engine_updater.py stage
python tools/sync_native_pins.py
cp upstream/engines.lock.json "$results/engines.lock.json"
{ uname -a; rustc --version; python -m pip freeze; } > "$results/environment.txt"
cargo build --locked --release --manifest-path native/artoffice_core/Cargo.toml
/usr/bin/time -v -o "$results/rust-memory.txt" \
  timeout 180 python tools/pdf_fidelity/raster_probe.py \
  native/artoffice_core/target/release/libartoffice_core.so \
  "$results/fixture" "$results/rust" > "$results/rust-render.txt"
python tools/pdf_fidelity/compare.py "$results"
python - "$results/rust-render.txt" <<'PY'
from pathlib import Path
import re, sys
rows = [dict(re.findall(r'(\w+)=(\d+)', line)) for line in Path(sys.argv[1]).read_text().splitlines()]
if len(rows) != 8 or any(row.get('warnings') != '0' for row in rows):
    raise SystemExit('Missing or warned Rust pages; review retained evidence')
PY
