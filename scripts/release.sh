#!/usr/bin/env bash
# Ainkrad for Mac: build, sign, (optionally) notarize, staple and describe a release (E12-2, D-38 as changed 2026-11-19).
# Runs on a GitHub-hosted Xcode 27 runner (.github/workflows/release.yml), which imports the Developer ID into a temporary keychain.
#   scripts/release.sh --check   validate tools, print what a run would do, build nothing
#   scripts/release.sh           build an UNSIGNED dmg under build/ (a dry run; Gatekeeper will complain)
#   scripts/release.sh --release signed dmg, optional notarization, Sparkle appcast and signed latest.json, all under build/release/
# Env: SIGN_IDENTITY        default: the Developer ID Application identity in the keychain
#      SPARKLE_ED_PRIVATE_KEY the Sparkle EdDSA private key (generate_keys -x output); required for --release
#      ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8   App Store Connect API key: notarize + staple ONLY when all three are set, else the
#                             dmg ships signed but NOT notarized, with a loud warning (build/release/NOTARIZED says true or false)
#      NOTARY_PROFILE         a local notarytool keychain profile, used when the ASC_* variables are not set (a developer's Mac)
#      RELEASE_NOTES          plain-text file, one change per line "Title | one line under it" (the What's new sheet)
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
PROFILE=${NOTARY_PROFILE:-}
SIGN=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}
SPARKLE_BIN=${SPARKLE_BIN:-}

missing=0
for t in xcodegen xcodebuild hdiutil codesign xcrun; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; missing=1; }; done
if [ "$mode" = --release ]; then
  [ -n "$SIGN" ] || { echo "no Developer ID Application identity in the keychain (set SIGN_IDENTITY)" >&2; missing=1; }
  [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] || { echo "SPARKLE_ED_PRIVATE_KEY is not set" >&2; missing=1; }
  [ -n "${RELEASE_TAG:-}" ] && [ "$RELEASE_TAG" != "app-v$VERSION" ] && { echo "tag $RELEASE_TAG does not match MARKETING_VERSION $VERSION" >&2; missing=1; }
fi
plan() {
  echo "1. xcodegen generate, then nice -n 19 xcodebuild Release (unsigned, build $BUILD) into $DD"
  echo "2. sign inside out, no --deep: Contents/Helpers/*, Sparkle's XPC/Updater/Autoupdate and framework, then Ainkrad.app with App/Mac/Ainkrad.entitlements"
  echo "3. hdiutil create $DMG, sign it; notarytool submit + stapler staple ONLY with ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_P8 (or NOTARY_PROFILE), else a loud warning"
  echo "4. generate_appcast (signed feed, Sparkle EdDSA key from SPARKLE_ED_PRIVATE_KEY) into $OUT: Ainkrad-$VERSION.dmg, appcast.xml, latest.json + latest.json.sig, NOTARIZED"
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
notarized=false
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_P8:-}" ]; then
  p8=$(mktemp); umask 077; printf '%s\n' "$ASC_KEY_P8" >"$p8"
  xcrun notarytool submit "$DMG" --key "$p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait || { rm -f "$p8"; echo "notarization failed (an HTTP 403 \"agreement\" means the Account Holder must accept Apple's pending agreement)" >&2; exit 1; }
  rm -f "$p8"; xcrun stapler staple "$DMG"; notarized=true
elif [ -n "$PROFILE" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait && xcrun stapler staple "$DMG" && notarized=true || { echo "notarization with profile $PROFILE failed" >&2; exit 1; }
else
  echo "::warning::NOT NOTARIZED: no App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8). The dmg is signed but Gatekeeper will warn on first open." >&2
fi

# The appcast (a SIGNED feed, SURequireSignedFeed) and the signed latest.json the ainkrad.io Worker and the download page trust.
# The EdDSA key reaches the Sparkle tools as a 0600 temp file and is shredded; it is never an argument or printed.
SPARKLE_BIN=${SPARKLE_BIN:-$(find "$DD/SourcePackages/artifacts" -path '*Sparkle/bin' -type d 2>/dev/null | head -1)}   # SPM fetched it during the build
[ -n "$SPARKLE_BIN" ] && [ -x # The dmg is on the GitHub release (over the 100 MB a Worker upload takes); ainkrad.io keeps the small signed pointers.
"$SPARKLE_BIN/generate_appcast" ] || { echo "no Sparkle tools: build once so SPM fetches Sparkle, or set SPARKLE_BIN" >&2; exit 1; }
key=$(mktemp); trap 'rm -f "$key"' EXIT; printf '%s' "$SPARKLE_ED_PRIVATE_KEY" >"$key"
rm -rf "$OUT"; mkdir -p "$OUT"; cp "$DMG" "$OUT/"
[ -z "${RELEASE_NOTES:-}" ] || cp "$RELEASE_NOTES" "$OUT/Ainkrad-$VERSION.txt"
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$key" --download-url-prefix "https://github.com/AinkradHQ/AinkradCoreApp/releases/download/app-v$VERSION/" --embed-release-notes "$OUT"
rm -f "$OUT/Ainkrad-$VERSION.txt"
printf '{"generated":%s,"version":"%s","build":%s,"notarized":%s}\n' "$(date +%s)" "$VERSION" "$BUILD" "$notarized" >"$OUT/latest.json"
sig=$("$SPARKLE_BIN/sign_update" --ed-key-file "$key" "$OUT/latest.json" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
[ -n "$sig" ] || { echo "could not sign latest.json" >&2; exit 1; }
printf '%s\n' "$sig" >"$OUT/latest.json.sig"; echo "$notarized" >"$OUT/NOTARIZED"
echo "release files in $OUT: $(ls "$OUT" | tr '\n' ' ') (notarized: $notarized)"
