#!/usr/bin/env bash
# Xcode build phase: puts ainkrad-runner and ainkrad-ptyhost in Ainkrad.app/Contents/Helpers, the two agent plists in
# Contents/Library/LaunchAgents, and signs the helpers with the app's identity (hardened runtime, no entitlements: release.sh signs them again, never with --deep). No binary is in git.
# Where the binaries come from, first match wins:
#   AINKRAD_RUNNER_DIR=<dir>   a folder holding both (a `cargo build --release -p ainkrad-runner -p ainkrad-ptyhost` target dir)
#   scripts/runner.pin         the pinned release asset, downloaded and checked against its SHA-256 (cached in build/runner-cache)
# With neither, a Debug build goes on without a runner (the app then says "no runner inside"); a Release build fails.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${TARGET_BUILD_DIR:?run from Xcode}/${CONTENTS_FOLDER_PATH:?}
HELPERS=$APP/Helpers
AGENTS=$APP/Library/LaunchAgents
rm -rf "$HELPERS" "$AGENTS"

skip() {
  echo "warning: bundle-runner: $1" >&2
  [ "${CONFIGURATION:-Debug}" != Release ] || { echo "error: bundle-runner: a Release build needs the runner" >&2; exit 1; }
  exit 0
}

src=${AINKRAD_RUNNER_DIR:-}
if [ -z "$src" ]; then
  # shellcheck disable=SC1091
  . "$ROOT/scripts/runner.pin"
  [ -n "${VERSION:-}" ] && [ -n "${SHA256_ARM64:-}" ] || skip "no AINKRAD_RUNNER_DIR and no pinned release in scripts/runner.pin"
  [ "$(uname -m)" = arm64 ] || skip "the pinned runner is arm64 only"
  # The app starts the runner with flags of its own release (--bundled came in 0.10): a runner pinned from an older Core
  # release exits at once on every Mac. A Release build of app X.Y must bundle runner X.Y (2026-11-21: 0.10 shipped 0.9.0).
  if [ "${CONFIGURATION:-Debug}" = Release ] && [ "${MARKETING_VERSION%.*}" != "${VERSION%.*}" ]; then
    echo "error: bundle-runner: the app is ${MARKETING_VERSION:-?} but scripts/runner.pin bundles runner $VERSION; pin the ${MARKETING_VERSION%.*} Core release" >&2
    exit 1
  fi
  name=ainkrad-runner-$VERSION-macos-arm64
  cache=$ROOT/build/runner-cache/$VERSION
  mkdir -p "$cache"
  if [ ! -f "$cache/$name.zip" ]; then
    # ainkrad.io first (E12-1), then the GitHub release (core-vX.Y.Z since E12-4b, vX.Y.Z before): the checksum below holds either way.
    curl -fsSL -o "$cache/$name.zip.part" "https://ainkrad.io/releases/core/$VERSION/$name.zip" \
      || curl -fsSL -o "$cache/$name.zip.part" "https://github.com/AinkradHQ/AinkradCore/releases/download/core-v$VERSION/$name.zip" \
      || curl -fsSL -o "$cache/$name.zip.part" "https://github.com/AinkradHQ/AinkradCore/releases/download/v$VERSION/$name.zip"
    mv "$cache/$name.zip.part" "$cache/$name.zip"
  fi
  got=$(shasum -a 256 "$cache/$name.zip" | cut -d' ' -f1)
  [ "$got" = "$SHA256_ARM64" ] || { rm -f "$cache/$name.zip"; echo "error: bundle-runner: checksum of $name.zip is $got, expected $SHA256_ARM64" >&2; exit 1; }
  rm -rf "$cache/unpacked"
  ditto -x -k "$cache/$name.zip" "$cache/unpacked"
  # The Core release zip holds the two binaries at its root; a mac-package.sh zip has them in <name>/bin.
  src=$cache/unpacked; [ -d "$src/$name/bin" ] && src=$src/$name/bin
fi
for b in ainkrad-runner ainkrad-ptyhost; do
  [ -x "$src/$b" ] || skip "no $b in $src"
done
# The binary inside must be the one pinned (and must run): a zip with another build in it fails here, not on a user's Mac.
if [ -n "${VERSION:-}" ] && [ -z "${AINKRAD_RUNNER_DIR:-}" ]; then
  have=$("$src/ainkrad-runner" --version 2>/dev/null | awk '{print $2}')
  [ "$have" = "$VERSION" ] || { echo "error: bundle-runner: the pinned zip holds runner '${have:-none}', expected $VERSION" >&2; exit 1; }
fi

mkdir -p "$HELPERS" "$AGENTS"
for b in ainkrad-runner ainkrad-ptyhost; do
  install -m 0755 "$src/$b" "$HELPERS/$b"
  codesign --force --options runtime --timestamp=none -s "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$HELPERS/$b"
done
cp "$ROOT"/App/Mac/LaunchAgents/*.plist "$AGENTS/"
echo "bundle-runner: runner and pty host from $src"
