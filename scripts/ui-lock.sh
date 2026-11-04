#!/usr/bin/env bash
# Runs a command that takes over the screen (XCUITest, snapshot walks) only when nobody is using this Mac: one at a time across
# every checkout (all their apps share one bundle id), and only once the keyboard and mouse have been idle for UI_IDLE seconds
# (default 300). UI_IDLE=0 runs as soon as the lock is free, for when you run it yourself.
#   scripts/ui-lock.sh <command...>
set -euo pipefail
LOCK=/private/tmp/claude-501/ainkrad-uitest.lock
LAST=/private/tmp/claude-501/ainkrad-uitest.last  # when the last run released the lock
IDLE=${UI_IDLE:-300}
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF / 1000000000); exit}'; }
if [ "${UI_LOCK_HELD:-}" != 1 ]; then
  until mkdir "$LOCK" 2>/dev/null; do
    p=$(cat "$LOCK/pid" 2>/dev/null || true)
    # A holder that died, or an old lock with no holder recorded, is cleared.
    if { [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; } || [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
      rm -rf "$LOCK"; continue
    fi
    sleep 15
  done
  echo $$ >"$LOCK/pid"
  trap 'date +%s >"$LAST"; rm -rf "$LOCK"' EXIT; trap 'exit 130' INT TERM
  # The tests' own synthetic input resets the idle clock: if nothing has happened since the last run ended, chain on.
  since=$(($(date +%s) - $(cat "$LAST" 2>/dev/null || echo 0)))
  [ "$since" -lt 600 ] && [ "$(idle)" -ge $((since - 5)) ] && IDLE=0
  said=
  while [ "$(idle)" -lt "$IDLE" ]; do
    [ -n "$said" ] || { echo "ui-lock: waiting until this Mac has been idle for ${IDLE}s (UI_IDLE=0 to skip)"; said=1; }
    sleep 20
  done
fi
UI_LOCK_HELD=1 "$@"
