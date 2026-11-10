#!/usr/bin/env bash
# Screenshots of the shell screens (home, launcher, bell, workspace, focus, settings, shortcuts) on the sample world.
# captures its own window, no Core needed. Runs under the shared UI-test lock (every checkout's app has the same bundle id).
#   OUT=<dir> scripts/shell-shots.sh [night|day|both]. Run `make build` first.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/private/tmp/claude-501/shell-shots}; mkdir -p "$OUT"
[ "${UI_LOCK_HELD:-}" = 1 ] || exec "$HERE/scripts/ui-lock.sh" "$0" "$@"
for THEME in $( [ "${1:-both}" = both ] && echo "dark light" || { [ "$1" = night ] && echo dark || echo light; } ); do
  echo "== $THEME -> $OUT"
  cd "$HERE"
  TEST_RUNNER_CORE_SHOTS=1 TEST_RUNNER_CORE_ALLOW_CAPTURE=1 TEST_RUNNER_CORE_DEMO=1 TEST_RUNNER_CORE_SNAPSHOT="$OUT" TEST_RUNNER_CORE_THEME="$THEME" \
    caffeinate -d nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -only-testing:AinkradCoreMacUITests/SnapshotWalkUITests test 2>&1 | grep -E "Test Case|error:|\*\* TEST" || true
done
