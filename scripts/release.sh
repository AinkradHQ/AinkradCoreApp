#!/usr/bin/env bash
# Ainkrad for Mac: build, sign, notarize, staple and describe a release (E12-2, D-38). Runs on the self-hosted release runner
# (Ahmed's Mac: Developer ID identity, notary profile and Sparkle key all live in its login keychain).
#   scripts/release.sh --check   validate tools, print what a run would do, build nothing
#   scripts/release.sh           build an UNSIGNED dmg under build/ (a dry run; Gatekeeper will complain)
#   scripts/release.sh --release signed + notarized + stapled dmg, then the Sparkle appcast, all under build/release/
# Env: SIGN_IDENTITY   default: the Developer ID Application identity in the keychain
#      NOTARY_PROFILE  default AinkradNotary (xcrun notarytool store-credentials)
#      RELEASE_NOTES   a plain-text file, one change per line "Title | one line under it" (what the app's What's new sheet shows)
# Never uploads, tags or bumps a version: the workflow uploads build/release/* with its own token.
# Signing is inside out and never with --deep: the helpers (runner, pty host), Sparkle's nested code and framework, then the app
# with its entitlements.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mode=${1:-dry}
VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(git rev-list --count HEAD)   # CFBundleVersion: Sparkle compares it, so it only ever grows
DD=build/dmg-dd; STAGE=build/dmg-stage; OUT=build/release; DMG=build/Ainkrad-$VERSION.dmg
APP=$DD/Build/Products/Release/Ainkrad.app
PROFILE=${NOTARY_PROFILE:-AinkradNotary}
SIGN=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}
SPARKLE_BIN=${SPARKLE_BIN:-$(find "$DD/SourcePackages/artifacts" -path '*Sparkle/bin' -type d 2>/dev/null | head -1)}

missing=0
for t in xcodegen xcodebuild hdiutil codesign xcrun; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; missing=1; }; done
if [ "$mode" = --release ]; then
  [ -n "$SIGN" ] || { echo "no Developer ID Application identity in the keychain (set SIGN_IDENTITY)" >&2; missing=1; }
  [ -n "${RELEASE_TAG:-}" ] && [ "$RELEASE_TAG" != "app-v$VERSION" ] && { echo "tag $RELEASE_TAG does not match MARKETING_VERSION $VERSION" >&2; missing=1; }
fi
plan() {
  echo "1. xcodegen generate, then nice -n 19 xcodebuild Release (unsigned, build $BUILD) into $DD"
  echo "2. sign inside out, no --deep: Contents/Helpers/*, Sparkle's XPC/Updater/Autoupdate and framework, then Ainkrad.app with App/Mac/Ainkrad.entitlements"
  echo "3. hdiutil create $DMG, sign it, notarytool submit --keychain-profile $PROFILE --wait, stapler staple"
  echo "4. generate_appcast (Sparkle EdDSA key from the login keychain) into $OUT: Ainkrad-$VERSION.dmg + appcast.xml"
  echo "Not done, ever, by this script: upload, tag, GitHub release, version bump."
}
if [ "$mode" = --check ]; then plan; [ $missing = 0 ] && echo "check: ok" || { echo "check: FAILED" >&2; exit 1; }; exit; fi
[ $missing = 0 ] || exit 1

xcodegen generate --quiet
nice -n 19 xcodebuild -project AinkradCore.xcodeproj -scheme AinkradCoreMac -configuration Release \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$BUILD" -quiet build

sign() { codesign --force --options runtime --timestamp --sign "$SIGN" "$@"; }
if [ "$mode" = --release ]; then
  for h in "$APP"/Contents/Helpers/*; do [ -f "$h" ] && sign "$h"; done
  # Sparkle: deepest first (its XPC services and helper app, then the framework itself). Whatever is there is signed.
  for fw in "$APP"/Contents/Frameworks/*.framework; do
    [ -d "$fw" ] || continue
    for n in "$fw"/Versions/*/XPCServices/*.xpc "$fw"/Versions/*/Updater.app "$fw"/Versions/*/Autoupdate; do [ -e "$n" ] && sign "$n"; done
    sign "$fw"
  done
  sign --entitlements App/Mac/Ainkrad.entitlements "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Ainkrad.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Ainkrad -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
if [ "$mode" != --release ]; then echo "built $DMG (unsigned dry run)"; exit 0; fi

sign "$DMG"
if ! xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait; then
  echo "notarization failed. HTTP 403 \"agreement\" means the Account Holder must accept Apple's pending agreement (runbook step 0)." >&2
  exit 1
fi
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# The appcast: only this version's archive is kept beside it (Sparkle needs just the newest entry). The EdDSA key is read
# from the login keychain by generate_appcast itself; no key is ever passed or printed.
[ -n "$SPARKLE_BIN" ] && [ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "no Sparkle tools (generate_appcast): build once so SPM fetches Sparkle, or set SPARKLE_BIN" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"; cp "$DMG" "$OUT/"
[ -z "${RELEASE_NOTES:-}" ] || cp "$RELEASE_NOTES" "$OUT/Ainkrad-$VERSION.txt"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://ainkrad.io/releases/app/" --embed-release-notes "$OUT"
rm -f "$OUT/Ainkrad-$VERSION.txt"
echo "release files in $OUT: $(ls "$OUT" | tr '\n' ' ')"
