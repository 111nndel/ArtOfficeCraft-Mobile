#!/usr/bin/env bash
set -euo pipefail

# A development-only experiment in a separate Cargo workspace. No renderer,
# dependency or binary from this probe is installed into the application.
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
task_root="$PWD/build/pdf-renderer-probe"
results="$task_root/results"
mkdir -p "$results"
cp upstream/engines.lock.json "$results/engines.lock.json"
{ uname -a; rustc --version; lscpu; } > "$results/environment.txt"
export CARGO_TARGET_DIR="$task_root/target"
cargo build --locked --release --manifest-path "$source_dir/Cargo.toml" \
  -p pdfcraft-render --example synth_sheet --example page_timing
"$CARGO_TARGET_DIR/release/examples/synth_sheet" "$results/synthetic.pdf" 10000 \
  > "$results/fixture.txt"
for scenario in load thumb backdrop tiles100; do
  /usr/bin/time -v -o "$results/$scenario-memory.txt" \
    timeout 180 "$CARGO_TARGET_DIR/release/examples/page_timing" \
    "$results/synthetic.pdf" "$scenario" 3 1 > "$results/$scenario.txt"
done
python - <<'PY'
import json
import re
from pathlib import Path
root = Path('build/pdf-renderer-probe/results')
report = {'platform': 'linux-x86_64', 'threads': 1, 'syntheticStrokes': 10000,
          'scope': 'Feasibility and resource measurements only; no visual-fidelity or Android claim.',
          'scenarios': {}}
for scenario in ('load', 'thumb', 'backdrop', 'tiles100'):
    rows = []
    for line in (root / f'{scenario}.txt').read_text().splitlines():
        if line.startswith('round='):
            fields = dict(re.findall(r'(\w+)=([^\s]+)', line))
            if fields.get('errors') != '0':
                raise RuntimeError(f'Render failed: {scenario}: {line}')
            rows.append(fields)
    if len(rows) != 3 or len({r['hash'] for r in rows}) != 1:
        raise RuntimeError(f'Missing or unstable render results: {scenario}')
    memory = (root / f'{scenario}-memory.txt').read_text()
    match = re.search(r'Maximum resident set size \(kbytes\): (\d+)', memory)
    if not match:
        raise RuntimeError(f'Missing peak memory: {scenario}')
    report['scenarios'][scenario] = {'rounds': rows, 'peakRssKiB': int(match[1])}
(root / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
PY
