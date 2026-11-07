#!/usr/bin/env bash
set -euo pipefail

# Framework source is pinned, including the engine/Dart artifact revisions.
sdk="${RUNNER_TEMP:?}/flutter"
git clone --quiet --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git "$sdk"
test "$(git -C "$sdk" rev-parse HEAD)" = c197ca5199e9ee5661e865596c9c07294dfab51c
echo "$sdk/bin" >> "${GITHUB_PATH:?}"
export PATH="$sdk/bin:$PATH"
flutter config --no-analytics
dart --disable-analytics
flutter --version
flutter pub get --enforce-lockfile
