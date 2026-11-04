#!/usr/bin/env bash
# Live test of the Mac app against a real local Core (E5-04). Starts a throwaway Core (fresh `init`, loopback, free port) in
# $APP_IT_DIR, never the real state dir, bootstraps a first admin device with ainkradctl, makes a pairing code for the app and
# plays the approver. Modes:
#   scripts/app-it.sh uitest   pairs the app end to end through XCUITest (CORE_IT=1): code typed, check code compared,
#                              approved with ainkradctl, Devices lists this Mac
#   scripts/app-it.sh terminals  adds a runner with a pty driver to the Core, then (1) CoreKit's live terminal test (open, echo,
#                              detach, reattach after the last byte, close) and (2) the app's XCUITest: New terminal, type
#                              echo, see it, Detach, Attach here, End terminal. Needs ainkrad-runner and ainkrad-ptyhost built.
#   scripts/app-it.sh admin    (E5-07) the app's XCUITest against the Core: toggles a feature switch, stores a dummy secret named
#                              e5-07-test, sees its metadata and the audit rows; then ainkradctl confirms the secret is there
#                              (name and metadata only: a value never comes back)
#   scripts/app-it.sh accounts (E5-08) the app's XCUITest against the Core: lists accounts (none) and pools, makes a pool, binds an
#                              agent to it, unbinds, deletes the pool. A throwaway Core holds no provider key, so no account is
#                              made: this app never takes a key.
#   scripts/app-it.sh shots    runs the app's self-snapshot walk (CORE_PAIR_SNAPSHOT, launched by XCUITest for its window
#                              server) against the Core; THEME=light|dark,
#                              OUT=<dir> for the PNGs; a second device claims the app's Add device code
#   scripts/app-it.sh agents   (E5-06) pairs the app, starts a runner with a stand-in `claude` (no provider, no credentials: it
#                              prints a few events and asks for one approval), then the app is driven by XCUITest: the list,
#                              a session started from outside appears over the event stream, ⌘Return approves it (step-up
#                              included), the session ends, a second session is cancelled from the app, an offline runner
#                              refuses a new one. `agents-core` does the Core side alone with ainkradctl.
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
if [ ! -x "$SRV" ] || [ ! -x "$CTL" ] || { { [ "$MODE" = terminals ] || [[ $MODE == agents* ]]; } && { [ ! -x "$RUN" ] || [ ! -x "$PTYH" ]; }; }; then
  (cd "$CORE" && nice -n 19 env CARGO_BUILD_JOBS=2 CARGO_PROFILE_DEV_DEBUG=line-tables-only \
    cargo build -q -p ainkrad-core-server -p ainkrad-ctl -p ainkrad-runner -p ainkrad-ptyhost)
fi

W=${APP_IT_DIR:-/private/tmp/claude-501/app-it-$(basename "$HERE")}
rm -rf "$W"; mkdir -p "$W"; chmod 700 "$W"
PIDS=()
PTY_BEFORE=$(pgrep ainkrad-ptyhost 2>/dev/null | sort || true)
cleanup() {
  local p
  for p in ${PIDS[@]+"${PIDS[@]}"}; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
  sleep 0.5
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill -9 "$p" 2>/dev/null || true; done
  for p in $(pgrep ainkrad-ptyhost 2>/dev/null | sort | comm -13 <(echo "$PTY_BEFORE") - ); do kill "$p" 2>/dev/null || true; done
  # Only the app built from this checkout: other worktrees may be running their own tests on the same Mac.
  pkill -f "$HERE/build/Build/Products/Debug/Ainkrad Core.app/Contents/MacOS" 2>/dev/null || true
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
PLAIN=; { [ "$MODE" = terminals ] || [[ $MODE == agents* ]]; } && PLAIN=--allow-plain-runner  # a loopback runner pairs over plain http
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

# A runner with a stand-in `claude`: no provider, no credentials. It prints an assistant message, one tool call and its result,
# asks the Core for one approval (a push), says what it was told, and ends the turn.
prep_runner() {
  mkdir -p "$W/runner" "$W/bin"; chmod 700 "$W/runner"
  cat >"$W/bin/claude" <<'PERL'
#!/usr/bin/perl
$| = 1;
exit 0 if $ENV{AINKRAD_EXEC_PROBE};
if (grep { $_ eq "--version" } @ARGV) { print "2.1.400 (Claude Code)\n"; exit 0 }
<STDIN>; <STDIN>;
print qq({"type":"system","subtype":"init","session_id":"S1"}\n);
print qq({"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"Reading the repo before I change anything."}],"usage":{"input_tokens":120,"output_tokens":30}}}\n);
print qq({"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"cargo test -p citadel"}}],"usage":{"input_tokens":150,"output_tokens":60}}}\n);
select(undef, undef, undef, 0.6);
print qq({"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"test result: ok. 12 passed"}]}}\n);
print qq({"type":"control_request","request_id":"req1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git push -u origin feat/agents"}}}\n);
my $ok = 0;
while (my $l = <STDIN>) { if ($l =~ /control_response/) { $ok = ($l =~ /"allow"/) ? 1 : 0; last } }
my $say = $ok ? "Pushed the branch." : "Not allowed to push, stopping.";
print qq({"type":"assistant","message":{"id":"m3","content":[{"type":"text","text":"$say"}],"usage":{"input_tokens":300,"output_tokens":100}}}\n);
print qq({"type":"result","subtype":"success","is_error":false,"usage":{"input_tokens":300,"output_tokens":100}}\n);
select(undef, undef, undef, 0.4);
exit 0;
PERL
  chmod 755 "$W/bin/claude"
  a device add runner-1 --kind runner >"$W/radd.out" || { echo "runner add failed"; return 1; }
  "$RUN" pair "$URL" --code "$(field "$W/radd.out" code)" --state "$W/runner" >"$W/rpair.out" 2>&1 </dev/null &
  PIDS+=($!)
  wait_for 30 grep -Eq "[A-Z0-9]{4}(-[A-Z0-9]{4}){3}" "$W/rpair.out" || { echo "the runner printed no check code"; cat "$W/rpair.out"; return 1; }
  RSAS=$(grep -Eo "[A-Z0-9]{4}(-[A-Z0-9]{4}){3}" "$W/rpair.out" | head -n1)
  a device approve "$(field "$W/radd.out" pairing_id)" "$RSAS" >"$W/rapprove.out" 2>&1 || { echo "runner approve failed"; cat "$W/rapprove.out"; return 1; }
  wait_for 30 test -s "$W/runner/enrolment.json" || { echo "the runner was not enrolled"; cat "$W/rpair.out"; return 1; }
  PATH="$W/bin:$PATH" "$RUN" connect --state "$W/runner" --enable-agents >"$W/runner.log" 2>&1 </dev/null &
  PIDS+=($!)
  wait_for 40 bash -c "'$CTL' --url '$URL' --host '${URL#http://}' --keystore '$KS_A' --stepup-passphrase-file '$PASS_A' runner ls </dev/null | grep -q online" \
    || { echo "the runner did not come online"; a runner ls 2>&1 | head -5; sed 's/\x1b\[[0-9;]*m//g' "$W/runner.log" | grep -v untested | tail -n8 | cut -c1-240; return 1; }
  RUNNER_ID=$(a runner ls | awk '/online/ {print $1; exit}')
  echo "   runner $RUNNER_ID online with a stand-in claude"
}

if [ "$MODE" = agents-core ]; then
  prep_runner || exit 1
  echo "== agent session through ainkradctl (the Core side of E5-06)"
  a agent run "$RUNNER_ID" claude "bootstrap the thing" >"$W/run.out" 2>&1 || { echo "agent run failed"; cat "$W/run.out"; exit 1; }
  cat "$W/run.out"
  SID=$(grep -o 'as_[A-Za-z0-9]*' "$W/run.out" | head -n1)
  sleep 4
  a agent show "$SID"
  a agent tail "$SID" --no-follow | head -30
  exit 0
fi

if [ "$MODE" = agents ]; then
  prep_runner || exit 1
  # The first session comes from outside, a while after the app paired and showed the empty list: it must arrive over the event stream.
  ( wait_for 400 grep -q approved "$W/approve.out" || exit 1; sleep 30; for _ in $(seq 1 30); do a agent run "$RUNNER_ID" claude "bootstrap the thing" >"$W/run1.out" 2>&1 && break; sleep 4; done; echo "   session 1 started: $(head -c 60 "$W/run1.out")" ) &
  PIDS+=($!)
  if [ -n "${APP_IT_SAMPLE:-}" ]; then  # a stuck app: a stack sample of it, a while after the first session started
    ( wait_for 400 grep -q approved "$W/approve.out" || exit 1; sleep "$APP_IT_SAMPLE"
      P=$(pgrep -f "$HERE/build/Build/Products/Debug/Ainkrad Core.app/Contents/MacOS" | head -n1); [ -n "$P" ] && sample "$P" 3 -file "$W/sample.txt" >/dev/null 2>&1 ) &
    PIDS+=($!)
  fi
  echo "== xcodebuild test (CORE_IT=1): the agents screens against the Core and the runner"
  cd "$HERE"
  TEST_RUNNER_CORE_IT=1 TEST_RUNNER_CORE_IT_URL="$URL" TEST_RUNNER_CORE_IT_CODE="$CODE_BARE" TEST_RUNNER_CORE_IT_SAS_FILE="$SAS_FILE" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -resultBundlePath "$W/agents.xcresult" -only-testing:AinkradCoreMacUITests/AgentsLiveUITests test 2>&1 \
    | grep -E "Test Case|error:|TEST |\*\* TEST|XCTAssert"
  STATUS=${PIPESTATUS[0]}
  # The window shots the test kept, out of the result bundle (OUT=<dir> to keep them).
  if [ -n "${OUT:-}" ]; then
    xcrun xcresulttool export attachments --path "$W/agents.xcresult" --output-path "$OUT" >/dev/null 2>&1 || true
  fi
  echo "== done: xcodebuild exit $STATUS"
  exit "$STATUS"
fi

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
    -only-testing:AinkradCoreMacUITests/TerminalsLiveUITests test 2>&1 | grep -E -A40 "Test Case|error:|TEST |\*\* TEST|XCTAssert"
  STATUS=${PIPESTATUS[0]}
  echo "== done: xcodebuild exit $STATUS"
  exit "$STATUS"
fi
if [ "$MODE" = admin ]; then
  echo "== xcodebuild test (CORE_IT=1): the app toggles a switch, stores a dummy secret and reads the audit"
  cd "$HERE"
  TEST_RUNNER_CORE_IT=1 TEST_RUNNER_CORE_IT_URL="$URL" TEST_RUNNER_CORE_IT_CODE="$CODE_BARE" TEST_RUNNER_CORE_IT_SAS_FILE="$SAS_FILE" \
    TEST_RUNNER_CORE_IT_SHOTS="${OUT:-$W}" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -only-testing:AinkradCoreMacUITests/AdminLiveUITests test 2>&1 | grep -E -A40 "Test Case|error:|TEST |\*\* TEST|XCTAssert"
  STATUS=${PIPESTATUS[0]}
  echo "== the Core's view: secrets (name and metadata only)"
  LS=$(a secret ls 2>&1) || true
  echo "$LS"
  echo "$LS" | grep -q "e5-07-test" || { echo "the Core does not list e5-07-test"; STATUS=1; }
  echo "== done: xcodebuild exit $STATUS"
  exit "$STATUS"
fi
if [ "$MODE" = accounts ]; then
  echo "== xcodebuild test (CORE_IT=1): the app makes a pool, binds an agent, unbinds and deletes the pool"
  cd "$HERE"
  TEST_RUNNER_CORE_IT=1 TEST_RUNNER_CORE_IT_URL="$URL" TEST_RUNNER_CORE_IT_CODE="$CODE_BARE" TEST_RUNNER_CORE_IT_SAS_FILE="$SAS_FILE" \
    TEST_RUNNER_CORE_IT_SHOTS="${OUT:-$W}" \
    nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Debug -derivedDataPath build \
    -only-testing:AinkradCoreMacUITests/AccountsLiveUITests test 2>&1 | grep -E -A40 "Test Case|error:|TEST |\*\* TEST|XCTAssert"
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
