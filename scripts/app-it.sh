#!/usr/bin/env bash
# Live test of the Mac app against a real local Core (E5-04). Starts a throwaway Core (fresh `init`, loopback, free port) in
# $APP_IT_DIR, never the real state dir, bootstraps a first admin device with ainkradctl, makes a pairing code for the app and
# plays the approver. Modes:
#   scripts/app-it.sh uitest   pairs the app end to end through XCUITest (CORE_IT=1): code typed, check code compared,
#                              approved with ainkradctl, Devices lists this Mac
#   scripts/app-it.sh terminals  adds a runner with a pty driver to the Core, then (1) CoreKit's live terminal test (open, echo,
#                              detach, reattach after the last byte, close) and (2) the app's XCUITest: New terminal, type
#                              echo, see it, Detach, Attach here, End terminal. Needs ainkrad-runner and ainkrad-ptyhost built.
#   scripts/app-it.sh shots    runs the app's self-snapshot walk (CORE_PAIR_SNAPSHOT, launched by XCUITest for its window
#                              server) against the Core; THEME=light|dark,
#                              OUT=<dir> for the PNGs; a second device claims the app's Add device code
# The app keeps its keys in memory (CORE_KEYSTORE=memory): the Keychain is never touched. Run `make build` first.
#   (CORE=<AinkradCore checkout> to override; APP_IT_KEEP=1 keeps the work dir.) Stops the Core and stray ptyhosts on exit.
# shellcheck disable=SC2015
set -euo pipefail

MODE=${1:-uitest}
HERE=$(cd "$(dirname "$0")/.." && pwd)
CORE=${CORE:-$HERE/../AinkradCore}
BIN=$CORE/target/debug
SRV=$BIN/ainkrad-core-server CTL=$BIN/ainkradctl RUN=$BIN/ainkrad-runner PTYH=$BIN/ainkrad-ptyhost
command -v cargo >/dev/null || PATH=/opt/homebrew/opt/rustup/bin:$PATH
if [ ! -x "$SRV" ] || [ ! -x "$CTL" ] || { [ "$MODE" = terminals ] && { [ ! -x "$RUN" ] || [ ! -x "$PTYH" ]; }; }; then
  (cd "$CORE" && nice -n 19 env CARGO_BUILD_JOBS=2 CARGO_PROFILE_DEV_DEBUG=line-tables-only \
    cargo build -q -p ainkrad-core-server -p ainkrad-ctl -p ainkrad-runner -p ainkrad-ptyhost)
fi

W=${APP_IT_DIR:-/private/tmp/claude-501/app-it}
rm -rf "$W"; mkdir -p "$W"; chmod 700 "$W"
PIDS=()
PTY_BEFORE=$(pgrep ainkrad-ptyhost 2>/dev/null | sort || true)
cleanup() {
  local p
  for p in ${PIDS[@]+"${PIDS[@]}"}; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
  sleep 0.5
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill -9 "$p" 2>/dev/null || true; done
  for p in $(pgrep ainkrad-ptyhost 2>/dev/null | sort | comm -13 <(echo "$PTY_BEFORE") - ); do kill "$p" 2>/dev/null || true; done
  pkill -f "Ainkrad Core.app/Contents/MacOS" 2>/dev/null || true
  if [ "${APP_IT_KEEP:-0}" = 1 ]; then echo "app-it: kept $W" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT

PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
URL=http://127.0.0.1:$PORT
HOME_DIR=$W/home DB=$W/home/core.db SOCK=$W/home/admin.sock
PASS_A=$W/pass-a KS_A=$W/a/keystore.json
openssl rand -hex 24 >"$PASS_A"; chmod 600 "$PASS_A"; mkdir -p "$W/a" "$W/b"
a() { "$CTL" --url "$URL" --host "${URL#http://}" --keystore "$KS_A" --stepup-passphrase-file "$PASS_A" "$@" </dev/null; }
field() { sed -n "s/^$2 //p" "$1" | head -n1; }
has_field() { [ -n "$(field "$1" "$2")" ]; }
wait_for() { local end=$((SECONDS + $1)); shift; until "$@" >/dev/null 2>&1; do [ "$SECONDS" -lt "$end" ] || return 1; sleep 0.1; done; }

echo "== core: init + serve on $URL (state in $HOME_DIR, not the real state dir)"
"$SRV" init "$HOME_DIR" >/dev/null 2>"$W/init.err"
PLAIN=; [ "$MODE" = terminals ] && PLAIN=--allow-plain-runner   # the runner pairs over loopback HTTP
"$SRV" serve --config "$HOME_DIR/config.toml" --listen "loopback:$PORT" $PLAIN 2>"$W/serve.log" >/dev/null &
PIDS+=($!)
wait_for 30 test -S "$SOCK" && wait_for 30 curl -fsS "$URL/healthz" || { echo "the Core did not start"; tail -n5 "$W/serve.log"; exit 1; }

echo "== first admin device: bootstrap + ainkradctl pair"
mkfifo "$W/boot.in"
"$SRV" bootstrap "$DB" admin <"$W/boot.in" >"$W/boot.out" 2>"$W/boot.err" &
BOOT=$!; PIDS+=("$BOOT")
exec 3>"$W/boot.in"
wait_for 20 has_field "$W/boot.out" code && wait_for 5 has_field "$W/boot.out" core_fp || { echo "bootstrap printed no code"; exit 1; }
CORE_FP=$(field "$W/boot.out" core_fp)
"$CTL" --socket "$SOCK" --host "127.0.0.1:$PORT" --keystore "$KS_A" --stepup-passphrase-file "$PASS_A" \
  pair "$(field "$W/boot.out" code)" --core-fp "$CORE_FP" >"$W/pair-a.out" 2>&1 </dev/null &
PAIR=$!; PIDS+=("$PAIR")
wait_for 20 has_field "$W/pair-a.out" sas && wait_for 20 has_field "$W/boot.out" sas || { echo "no SAS on both sides"; exit 1; }
[ "$(field "$W/pair-a.out" sas)" = "$(field "$W/boot.out" sas)" ] || { echo "the two SAS differ"; exit 1; }
echo y >&3; exec 3>&-
wait "$BOOT" && wait "$PAIR" || { echo "bootstrap or pair failed"; exit 1; }
[ "$(field "$W/pair-a.out" status)" = active ] || { echo "device A not active"; exit 1; }
echo "   admin device $(field "$W/pair-a.out" device) active, Core $CORE_FP"

# A runner with a pty driver, and a second device for CoreKit's live test (terminal scope, no admin).
if [ "$MODE" = terminals ]; then
  echo "== runner with pty: pair, approve, connect"
  RSTATE=$W/runner; mkdir -p "$W/tmp"
  a device add vm --kind runner >"$W/add-r.out" || { echo "runner device add failed"; exit 1; }
  "$RUN" pair "$URL" --code "$(field "$W/add-r.out" code)" --state "$RSTATE" >"$W/pair-r.out" 2>&1 </dev/null &
  PIDS+=($!); PR=$!
  runner_sas() { grep -E '^ +[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$' "$W/pair-r.out" | tr -d ' '; }
  wait_for 20 runner_sas || { echo "the runner showed no check code"; exit 1; }
  a device approve "$(field "$W/add-r.out" pairing_id)" "$(runner_sas)" >/dev/null || { echo "approving the runner failed"; exit 1; }
  wait "$PR" || { echo "the runner's pairing failed"; exit 1; }
  RID=$(sed -n 's/^Paired as \(d_[A-Za-z0-9]*\) with the Core.*/\1/p' "$W/pair-r.out")
  env TMPDIR="$W/tmp" AINKRAD_PTYHOST="$PTYH" "$RUN" connect --state "$RSTATE" --enable-pty >/dev/null 2>"$W/runner.log" </dev/null &
  PIDS+=($!)
  runner_up() { a --json runner show "$RID" | grep -q '"online": *true'; }
  wait_for 60 runner_up || { echo "the runner did not come online"; tail -n5 "$W/runner.log"; exit 1; }
  echo "   runner $RID online with pty"
  [ "${APP_IT_HOLD:-0}" = 1 ] && { echo "== holding for manual poking: W=$W URL=$URL RID=$RID"; sleep 3000; }
  a device add core-it --scopes read,terminal >"$W/add-ck.out" || { echo "device add failed"; exit 1; }
  CK_CODE=$(field "$W/add-ck.out" code) CK_PAIRING=$(field "$W/add-ck.out" pairing_id); CK_SAS=$W/ck.sas
  (
    wait_for 120 test -s "$CK_SAS" || exit 1
    a device approve "$CK_PAIRING" "$(cat "$CK_SAS")" >"$W/approve-ck.out" 2>&1 || { echo "   approver: CoreKit device failed"; exit 1; }
  ) &
  PIDS+=($!)
  echo "== CoreKit live terminal test (CORE_IT=1)"
  (cd "$HERE/Packages/CoreKit" && CORE_IT=1 CORE_IT_TERMINALS=1 CORE_IT_URL="$URL" CORE_IT_CODE="${CK_CODE//-/}" CORE_IT_SAS_FILE="$CK_SAS" \
    nice -n 19 swift test --filter LiveTerminalTests 2>&1 | grep -E "IT |✔|✘|Issue|error:|Test run" ) || { echo "CoreKit live test failed"; exit 1; }
fi

echo "== pairing for the Mac app (scopes read,approve,admin,terminal,agent)"
a device add mac-app --scopes read,approve,admin,terminal,agent >"$W/add.out" || { echo "device add failed"; exit 1; }
CODE=$(field "$W/add.out" code) PAIRING=$(field "$W/add.out" pairing_id)
[ -n "$CODE" ] && [ -n "$PAIRING" ] || { echo "no code"; exit 1; }
CODE_BARE=${CODE//-/}
SAS_FILE=$W/app.sas ADD_CODE_FILE=$W/add.code LOCKS_FILE=$W/locks.ready

# The approver for the app: the app writes the check code it shows; type that into ainkradctl, as a person would.
(
  wait_for 120 test -s "$SAS_FILE" || exit 1
  echo "   approver: check code from the app $(cat "$SAS_FILE")"
  [ "$MODE" = shots ] && sleep 6
  a device approve "$PAIRING" "$(cat "$SAS_FILE")" >"$W/approve.out" 2>&1 || { echo "   approver: failed: $(tail -n2 "$W/approve.out")"; exit 1; }
  echo "   approver: approved the app"
) &
PIDS+=($!)

APP="$HERE/build/Build/Products/Debug/Ainkrad Core.app"
if [ "$MODE" = shots ]; then
  # The second device: claims the code the app's Add device shows (no step-up key); the app approves it.
  (
    wait_for 180 test -s "$ADD_CODE_FILE" || exit 1
    echo "   second device: claiming $(cat "$ADD_CODE_FILE")"
    "$CTL" --url "$URL" --host "${URL#http://}" --keystore "$W/b/keystore.json" pair "$(cat "$ADD_CODE_FILE")" \
      --no-stepup --wait 120 >"$W/pair-b.out" 2>&1 </dev/null || true
    echo "   second device: $(field "$W/pair-b.out" status)"
    # A few wrong codes from this address make the Core lock it: something for Lockouts to list.
    for i in $(seq 1 40); do
      "$CTL" --url "$URL" --host "${URL#http://}" --keystore "$W/b/k$i.json" pair ZZZZZ-ZZZZ"$((i % 10))" --no-stepup \
        >/dev/null 2>&1 </dev/null || true
      [ -n "$(a lockouts ls 2>/dev/null | head -n1)" ] && break
    done
    echo "   lockouts: $(a lockouts ls 2>&1 | head -n3 | tr '\n' ' ')"
    echo ready >"$LOCKS_FILE"
  ) &
  PIDS+=($!)
  OUT=${OUT:-$W/shots}; mkdir -p "$OUT"
  echo "== app self-snapshot walk (${THEME:-dark}) -> $OUT"
  cd "$HERE"
  TEST_RUNNER_CORE_SHOTS=1 TEST_RUNNER_CORE_PAIR_SNAPSHOT="$OUT" TEST_RUNNER_CORE_THEME="${THEME:-dark}" \
    TEST_RUNNER_CORE_IT_URL="$URL" TEST_RUNNER_CORE_IT_CODE="$CODE_BARE" TEST_RUNNER_CORE_IT_SAS_FILE="$SAS_FILE" \
    TEST_RUNNER_CORE_IT_ADD_CODE_FILE="$ADD_CODE_FILE" TEST_RUNNER_CORE_IT_LOCKS_READY="$LOCKS_FILE" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -only-testing:AinkradCoreMacUITests/SnapshotWalkUITests test 2>&1 | grep -E "Test Case|error:|\*\* TEST" || true
  echo "== done: shots in $OUT"
  exit 0
fi

if [ "$MODE" = terminals ]; then
  echo "== xcodebuild test (CORE_IT=1): the app opens, uses, detaches, reattaches and ends a terminal"
  cd "$HERE"
  TEST_RUNNER_CORE_IT=1 TEST_RUNNER_CORE_IT_URL="$URL" TEST_RUNNER_CORE_IT_CODE="$CODE_BARE" TEST_RUNNER_CORE_IT_SAS_FILE="$SAS_FILE" \
    TEST_RUNNER_CORE_IT_SHOTS="${OUT:-$W}" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -only-testing:AinkradCoreMacUITests/TerminalsLiveUITests test 2>&1 | grep -E "Test Case|error:|TEST |\*\* TEST|XCTAssert"
  STATUS=${PIPESTATUS[0]}
  echo "== done: xcodebuild exit $STATUS"
  exit "$STATUS"
fi
echo "== xcodebuild test (CORE_IT=1): the app pairs end to end"
cd "$HERE"
TEST_RUNNER_CORE_IT=1 TEST_RUNNER_CORE_IT_URL="$URL" TEST_RUNNER_CORE_IT_CODE="$CODE_BARE" TEST_RUNNER_CORE_IT_SAS_FILE="$SAS_FILE" \
  nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
  -only-testing:AinkradCoreMacUITests/PairingLiveUITests test 2>&1 | grep -E "Test Case|error:|TEST |\*\* TEST|XCTAssert" 
STATUS=${PIPESTATUS[0]}
echo "== done: xcodebuild exit $STATUS"
exit "$STATUS"
