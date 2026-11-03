#!/usr/bin/env bash
# Live integration test of CoreKit against a real local Core (E5-02). Runs `swift test` with CORE_IT=1 after
#   1 starting a throwaway Core (fresh `init`, loopback on a free port) in $CORE_IT_DIR, never the real state dir
#   2 bootstrapping the first device with ainkradctl (the host verb `bootstrap`, then `ainkradctl pair`)
#   3 making a pairing code for the Swift client with `ainkradctl device add`
#   4 while the Swift test claims it and writes its SAS to a file, approving it with ainkradctl (SAS typed from that file)
#   5 once the Swift test's event stream is live, doing something that makes an event (a second pairing)
# The Swift test then checks: session, GET /api/v1/me, event replay, a WebSocket event, a session refresh, Core pinning.
#   scripts/core-it.sh              (CORE=<AinkradCore checkout> to override; CORE_IT_DIR=<work dir>; CORE_IT_KEEP=1 keeps it)
# Binaries come from $CORE/target/debug; missing ones are built niced with CARGO_BUILD_JOBS=2.
# shellcheck disable=SC2015
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
CORE=${CORE:-$HERE/../AinkradCore}
BIN=$CORE/target/debug
SRV=$BIN/ainkrad-core-server CTL=$BIN/ainkradctl
command -v cargo >/dev/null || PATH=/opt/homebrew/opt/rustup/bin:$PATH
if [ ! -x "$SRV" ] || [ ! -x "$CTL" ]; then
  (cd "$CORE" && nice -n 19 env CARGO_BUILD_JOBS=2 CARGO_PROFILE_DEV_DEBUG=line-tables-only \
    cargo build -q -p ainkrad-core-server -p ainkrad-ctl)
fi
command -v jq >/dev/null || { echo "core-it: needs jq" >&2; exit 2; }

W=${CORE_IT_DIR:-/private/tmp/claude-501/corekit-it}
rm -rf "$W"; mkdir -p "$W"; chmod 700 "$W"
PIDS=()
PTY_BEFORE=$(pgrep ainkrad-ptyhost 2>/dev/null | sort || true)
cleanup() {
  local p
  for p in ${PIDS[@]+"${PIDS[@]}"}; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
  sleep 0.5
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill -9 "$p" 2>/dev/null || true; done
  # Any ptyhost this run started (there should be none: no terminal is opened).
  for p in $(pgrep ainkrad-ptyhost 2>/dev/null | sort | comm -13 <(echo "$PTY_BEFORE") - ); do kill "$p" 2>/dev/null || true; done
  if [ "${CORE_IT_KEEP:-0}" = 1 ]; then echo "core-it: kept $W" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT

PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
URL=http://127.0.0.1:$PORT
HOME_DIR=$W/home DB=$W/home/core.db SOCK=$W/home/admin.sock
PASS_A=$W/pass-a KS_A=$W/a/keystore.json
openssl rand -hex 24 >"$PASS_A"; chmod 600 "$PASS_A"; mkdir -p "$W/a"
a() { "$CTL" --url "$URL" --host "${URL#http://}" --keystore "$KS_A" --stepup-passphrase-file "$PASS_A" "$@" </dev/null; }
field() { sed -n "s/^$2 //p" "$1" | head -n1; }
has_field() { [ -n "$(field "$1" "$2")" ]; }
wait_for() { local end=$((SECONDS + $1)); shift; until "$@" >/dev/null 2>&1; do [ "$SECONDS" -lt "$end" ] || return 1; sleep 0.1; done; }

echo "== core: init + serve on $URL (state in $HOME_DIR, not the real state dir)"
"$SRV" init "$HOME_DIR" >/dev/null 2>"$W/init.err"
"$SRV" serve --config "$HOME_DIR/config.toml" --listen "loopback:$PORT" 2>"$W/serve.log" >/dev/null &
PIDS+=($!)
wait_for 30 test -S "$SOCK" && wait_for 30 curl -fsS "$URL/healthz" || { echo "the Core did not start"; tail -n5 "$W/serve.log"; exit 1; }

echo "== first device: bootstrap + ainkradctl pair (SAS compared on the host)"
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
wait "$BOOT" && wait "$PAIR" || { echo "bootstrap or pair failed"; tail -n3 "$W/pair-a.out"; exit 1; }
[ "$(field "$W/pair-a.out" status)" = active ] || { echo "device A not active"; exit 1; }
echo "   device A $(field "$W/pair-a.out" device) active, Core $CORE_FP"

echo "== pairing for the Swift client (scopes read,approve,admin: audit events need admin)"
a device add swift-corekit --scopes read,approve,admin >"$W/add.out" || { echo "device add failed"; exit 1; }
CODE=$(field "$W/add.out" code) PAIRING=$(field "$W/add.out" pairing_id)
[ -n "$CODE" ] && [ -n "$PAIRING" ] || { echo "no code"; exit 1; }

SAS_FILE=$W/swift.sas LIVE_FILE=$W/swift.live
# The approver: the Swift side writes its SAS (computed from its own keys); type that into ainkradctl, as a person would.
(
  wait_for 120 test -s "$SAS_FILE" || exit 1
  echo "   approver: SAS from the Swift client $(cat "$SAS_FILE")"
  a device approve "$PAIRING" "$(cat "$SAS_FILE")" >"$W/approve.out" 2>&1 || { echo "   approver: approve failed: $(tail -n2 "$W/approve.out")"; exit 1; }
  echo "   approver: approved"
  # The event: once the Swift event stream is live, start another pairing (audited, so an event).
  wait_for 120 test -s "$LIVE_FILE" || exit 1
  sleep 1
  a device add event-probe --scopes read >"$W/probe.out" 2>&1 && echo "   trigger: made another pairing (an event)"
) &
PIDS+=($!)

echo "== swift test (CORE_IT=1)"
cd "$HERE/Packages/CoreKit"
CORE_IT=1 CORE_IT_URL="$URL" CORE_IT_CODE="$CODE" CORE_IT_SAS_FILE="$SAS_FILE" CORE_IT_LIVE_FILE="$LIVE_FILE" \
  nice -n 19 swift test --filter LiveIntegrationTests 2>&1 | grep -E "^IT |✔|✘|error|Issue|passed|failed"
STATUS=${PIPESTATUS[0]}
echo "== done: swift test exit $STATUS"
exit "$STATUS"
