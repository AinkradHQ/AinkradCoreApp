#!/usr/bin/env bash
# Screenshots of every Leyline state on the stand-in data (LeylineDemo): the app captures its own window, no Core needed.
#   OUT=<dir> scripts/leyline-shots.sh [night|day|both] [reduce]   (SCENES=a,b limits the walk). Run `make build` first.
#   `reduce` only names the files -reduce: turn Reduce Motion on in System Settings first (the components follow it).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ "${UI_LOCK_HELD:-}" = 1 ] || exec "$HERE/scripts/ui-lock.sh" "$0" "$@"
OUT=${OUT:-/private/tmp/claude-501/leyline-shots}; mkdir -p "$OUT"
REDUCE=0; [ "${2:-}" = reduce ] && REDUCE=1
for THEME in $( [ "${1:-both}" = both ] && echo "dark light" || { [ "$1" = night ] && echo dark || echo light; } ); do
  echo "== $THEME reduce=$REDUCE -> $OUT"
  cd "$HERE"
  TEST_RUNNER_CORE_SHOTS=1 TEST_RUNNER_CORE_ALLOW_CAPTURE=1 TEST_RUNNER_CORE_DEMO=1 TEST_RUNNER_CORE_LEYLINE_SNAPSHOT="$OUT" TEST_RUNNER_CORE_THEME="$THEME" \
    TEST_RUNNER_CORE_REDUCE_MOTION="$REDUCE" TEST_RUNNER_CORE_LEYLINE_SCENES="${SCENES:-}" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build -jobs 2 ${XCODEBUILD_EXTRA:-} \
    -only-testing:AinkradCoreMacUITests/SnapshotWalkUITests test 2>&1 | grep -E "Test Case|error:|\*\* TEST" || true
done
