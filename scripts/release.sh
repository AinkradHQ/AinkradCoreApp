#!/usr/bin/env bash
# Ainkrad for Mac: build a Release .dmg under build/. DRY RUN by design (E5-12, KAN-56/217).
#   scripts/release.sh          build the unsigned dmg; sign + notarize + staple only if both env vars are set
#   scripts/release.sh --check  validate tools, print what a run would do, build nothing
# Env (read from the environment only, never stored, never printed):
#   SIGN_IDENTITY   Developer ID Application identity name, e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE  notarytool keychain profile name (xcrun notarytool store-credentials)
# Never uploads, tags, publishes, or bumps a version. Releases and notarisation stay with Ahmed.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
DD=build/dmg-dd; STAGE=build/dmg-stage; DMG=build/Ainkrad-$VERSION.dmg
APP=$DD/Build/Products/Release/Ainkrad.app
SIGN=${SIGN_IDENTITY:-}; PROFILE=${NOTARY_PROFILE:-}

missing=0
for t in xcodegen xcodebuild hdiutil codesign xcrun; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; missing=1; }
done
[ -n "$SIGN" ] && ! security find-identity -v -p codesigning | grep -qF "$SIGN" && { echo "SIGN_IDENTITY not found in keychain" >&2; missing=1; }

plan() {
  echo "1. xcodegen generate, then nice -n 19 xcodebuild Release (unsigned) into $DD"
  echo "2. stage Ainkrad.app + Applications symlink, hdiutil create $DMG"
  if [ -n "$SIGN" ] && [ -n "$PROFILE" ]; then
    echo "3. codesign app (hardened runtime) and dmg with SIGN_IDENTITY; notarytool submit --wait with NOTARY_PROFILE; stapler staple"
  else
    echo "3. SKIPPED signing: ${SIGN:+SIGN_IDENTITY set, }${SIGN:-SIGN_IDENTITY not set}"
    echo "   SKIPPED notarization + stapling: NOTARY_PROFILE ${PROFILE:+and SIGN_IDENTITY needed together}${PROFILE:-not set}"
    echo "   (dry run: the dmg is unsigned and will trigger Gatekeeper)"
  fi
  echo "Not done, ever, by this script: upload, tag, GitHub release, version bump."
}

if [ "${1:-}" = "--check" ]; then
  plan; [ $missing = 0 ] && echo "check: ok" || { echo "check: FAILED" >&2; exit 1; }; exit
fi
[ $missing = 0 ] || exit 1

xcodegen generate --quiet
nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Release \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO -quiet build

rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"

if [ -n "$SIGN" ] && [ -n "$PROFILE" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN" "$STAGE/Ainkrad.app"
fi
hdiutil create -quiet -volname Ainkrad -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [ -n "$SIGN" ] && [ -n "$PROFILE" ]; then
  codesign --force --timestamp --sign "$SIGN" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
rm -rf "$STAGE"
echo "built $DMG"; plan | sed -n '3,$p'
