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
python tools/engine_updater.py stage --engine pdfcraft
source_dir="$(python - <<'PY'
import json
from pathlib import Path
pin = json.loads(Path('upstream/engines.lock.json').read_text())['engines']['pdfcraft']
print(Path('upstream/staged/pdfcraft') / f"{pin['tag']}-{pin['commit'][:12]}")
PY
)"
# Add only a test consumer to Cargo's auto-discovered examples. Renderer src/
# stays untouched; this job's staged checkout never feeds application builds.
cp tools/pdf_fidelity/raster_probe.rs "$source_dir/crates/render/examples/artoffice_fidelity.rs"
sha256sum tools/pdf_fidelity/raster_probe.rs > "$results/consumer-sha256.txt"
cp upstream/engines.lock.json "$results/engines.lock.json"
{ uname -a; rustc --version; python -m pip freeze; } > "$results/environment.txt"
export CARGO_TARGET_DIR="$task_root/target"
cargo build --locked --release --manifest-path "$source_dir/Cargo.toml" \
  -p pdfcraft-render --example artoffice_fidelity
/usr/bin/time -v -o "$results/rust-memory.txt" \
  timeout 180 "$CARGO_TARGET_DIR/release/examples/artoffice_fidelity" \
  "$results/fixture/fixture.pdf" "$results/rust" 6 2 > "$results/rust-render.txt"
python tools/pdf_fidelity/compare.py "$results"
python - "$results/rust-render.txt" <<'PY'
from pathlib import Path
import re, sys
rows = [dict(re.findall(r'(\w+)=(\d+)', line)) for line in Path(sys.argv[1]).read_text().splitlines()]
if len(rows) != 6 or any(row.get('warnings') != '0' for row in rows):
    raise SystemExit('Missing or warned Rust pages; review retained evidence')
PY
