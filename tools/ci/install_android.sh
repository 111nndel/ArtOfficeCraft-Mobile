#!/usr/bin/env bash
set -euo pipefail
sdk="${ANDROID_HOME:?}"
for attempt in 1 2 3; do
  if "$sdk/cmdline-tools/latest/bin/sdkmanager" --install "$@"; then exit 0; fi
  if [[ "$attempt" == 3 ]]; then exit 1; fi
  echo "Android component download failed; retrying ($attempt/3)." >&2
  # Only disposable hosted runners: do not resume a truncated SDK archive.
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then rm -rf -- "$sdk/.temp"; fi
  sleep 5
done
