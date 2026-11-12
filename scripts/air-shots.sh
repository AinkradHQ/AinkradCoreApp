#!/usr/bin/env bash
# Run one snapshot walk of a built Debug app on the MacBook Air (`ssh air`) and pull the PNGs back. Builds nothing.
#   scripts/air-shots.sh <Ainkrad.app> <walk> [night|day] [outdir]
# walk: admin|home|agents|terminals|accounts|brain|pairing|shell|gallery   (default theme night, outdir ./air-shots)
# Prints the app's stderr (SNAP lines) from the Air; set SCENES=a,b to limit the admin walk.
set -euo pipefail
APP=${1:?usage: air-shots.sh <Ainkrad.app> <walk> [night|day] [outdir]}; WALK=${2:?walk}; THEME=${3:-night}; OUT=${4:-./air-shots}
case $WALK in
  admin) VAR=CORE_ADMIN_SNAPSHOT;; home) VAR=CORE_HOME_SNAPSHOT;; agents) VAR=CORE_AGENTS_SNAPSHOT;;
  terminals) VAR=CORE_TERM_SNAPSHOT;; accounts) VAR=CORE_ACC_SNAPSHOT;; brain) VAR=CORE_BRAIN_SNAPSHOT;;
  pairing) VAR=CORE_PAIR_SNAPSHOT;; shell) VAR=CORE_SNAPSHOT;; gallery) VAR=CORE_GALLERY_SNAPSHOT;;
  *) echo "unknown walk $WALK" >&2; exit 2;;
esac
[ "$THEME" = night ] && T=dark || T=light
REMOTE=/Users/alhasani/rig/walk-$WALK
mkdir -p "$OUT"
# One walk at a time on the Air: parallel lanes killed each other's app (pkill) and broke each other's rsync.
until ssh air 'mkdir /tmp/ainkrad-air-walk.lock' 2>/dev/null; do echo "waiting for the Air (another walk is running)" >&2; sleep 15; done
trap "ssh air 'rmdir /tmp/ainkrad-air-walk.lock' 2>/dev/null || true" EXIT
ssh air "pkill -x Ainkrad 2>/dev/null; rm -rf /tmp/ainkrad-snap.log $REMOTE ~/rig/walk-app ~/Library/Saved\\ Application\\ State/com.ainkrad.core.savedState; mkdir -p $REMOTE ~/rig/walk-app"
# The Air's GUI launchd domain keeps CORE_* vars from older rig runs (launchctl setenv). The app runs the FIRST walk whose
# var is set (gallery before admin), so a stale CORE_GALLERY_SNAPSHOT made every other walk run the gallery. Clear them.
ssh air 'V=$(launchctl print gui/501 | grep -o "CORE_[A-Z_]*" | sort -u | tr "\n" " "); [ -z "$V" ] && exit 0
  C=""; for v in $V; do C="$C /bin/launchctl unsetenv $v;"; done
  mkdir -p ~/Library/LaunchAgents; P=~/Library/LaunchAgents/rig.unset.plist
  printf "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Label</key><string>rig.unset</string><key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string><string>%s</string></array><key>RunAtLoad</key><true/></dict></plist>" "$C" > $P
  launchctl bootout gui/501/rig.unset 2>/dev/null; launchctl bootstrap gui/501 $P; sleep 1; rm -f $P'
rsync -a --delete "$APP/" air:rig/walk-app/Ainkrad.app/
ssh air "caffeinate -u -t 3; open -n --stdout $REMOTE/out.log --stderr $REMOTE/err.log \
  --env CORE_DEMO=1 --env CORE_SHOTS=1 --env CORE_ALLOW_CAPTURE=1 --env CORE_KEYSTORE=memory --env $VAR=$REMOTE \
  --env CORE_THEME=$T --env CORE_ADMIN_SCENES=${SCENES:-} ~/rig/walk-app/Ainkrad.app
  for i in \$(seq 90); do pgrep -x Ainkrad >/dev/null || break; sleep 2; done; pkill -x Ainkrad 2>/dev/null; true"
ssh air "cat /tmp/ainkrad-snap.log" || true
rsync -a --include='*.png' --exclude='*' air:"$REMOTE/" "$OUT/"
echo "$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') PNG(s) in $OUT"
