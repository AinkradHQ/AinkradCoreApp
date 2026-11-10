#!/usr/bin/env bash
# Screenshots of every brain state on the stand-in data (BrainDemo): the app captures its own window, no Core needed.
#   OUT=<dir> scripts/brain-shots.sh [night|day|both]   (SCENES=a,b limits the walk). Run `make build` first.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ "${UI_LOCK_HELD:-}" = 1 ] || exec "$HERE/scripts/ui-lock.sh" "$0" "$@"
OUT=${OUT:-/private/tmp/claude-501/brain-shots}; mkdir -p "$OUT"
for THEME in $( [ "${1:-both}" = both ] && echo "dark light" || { [ "$1" = night ] && echo dark || echo light; } ); do
  echo "== $THEME -> $OUT"
  cd "$HERE"
  TEST_RUNNER_CORE_SHOTS=1 TEST_RUNNER_CORE_ALLOW_CAPTURE=1 TEST_RUNNER_CORE_DEMO=1 TEST_RUNNER_CORE_BRAIN_SNAPSHOT="$OUT" TEST_RUNNER_CORE_THEME="$THEME" \
    TEST_RUNNER_CORE_BRAIN_SCENES="${SCENES:-}" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -only-testing:AinkradCoreMacUITests/SnapshotWalkUITests test 2>&1 | grep -E "Test Case|error:|\*\* TEST" || true
done
