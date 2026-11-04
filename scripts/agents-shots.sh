#!/usr/bin/env bash
# Screenshots of every agents screen and state (E5-06) from the app's own self-snapshot walk over the prototype's sample world
# (CORE_DEMO=1: no Core, no keys). THEME=dark|light, OUT=<dir>. Launched through XCUITest, which gives the app its window server.
# The app goes full screen on this Mac for about a minute; it sends no key events. Run `make build` first.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ "${UI_LOCK_HELD:-}" = 1 ] || exec "$HERE/scripts/ui-lock.sh" "$0" "$@"
OUT=${OUT:-/private/tmp/claude-501/agents-shots}
mkdir -p "$OUT"
cd "$HERE"
TEST_RUNNER_CORE_SHOTS=1 TEST_RUNNER_CORE_DEMO=1 TEST_RUNNER_CORE_AGENTS_SNAPSHOT="$OUT" TEST_RUNNER_CORE_THEME="${THEME:-dark}" \
  nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
  -only-testing:AinkradCoreMacUITests/SnapshotWalkUITests test 2>&1 | grep -E "Test Case|error:|\*\* TEST" || true
pkill -f "$HERE/build/Build/Products/Debug/Ainkrad.app/Contents/MacOS" 2>/dev/null || true
echo "shots in $OUT"
