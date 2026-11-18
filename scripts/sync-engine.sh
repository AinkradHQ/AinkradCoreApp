#!/bin/sh
# DesignEngine.xcframework for Packages/DesignCanvas (V3-02, plan T6). Git-ignored; pinned by scripts/engine.pin.
#   scripts/sync-engine.sh [DIR]   copy DIR/DesignEngine.xcframework into Packages/DesignCanvas/Vendor after checking it
#                                  against the pin (DIR default: $AINKRAD_ENGINE_DIR, else ../AinkradCore/target/engine,
#                                  where `make engine` puts it at the pinned CORE_COMMIT)
#   scripts/sync-engine.sh check   fail unless the vendored copy matches the pin (make build / make test run this)
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
pin="$root/scripts/engine.pin"
vendor="$root/Packages/DesignCanvas/Vendor"
sums() { grep -v '^#' "$pin" | grep -v '^CORE_COMMIT='; }
verify() { # DIR: the xcframework's files hash to the pinned sums
  (cd "$1" && sums | shasum -a 256 -c --quiet -) >/dev/null 2>&1
}
if [ "${1:-}" = check ]; then
  verify "$vendor" && exit 0
  echo "sync-engine: Packages/DesignCanvas/Vendor/DesignEngine.xcframework is missing or not the pinned build." >&2
  echo "  Build it in AinkradCore at $(grep '^CORE_COMMIT=' "$pin" | cut -d= -f2) with \`make engine\`, then run scripts/sync-engine.sh." >&2
  exit 1
fi
src="${1:-${AINKRAD_ENGINE_DIR:-$root/../AinkradCore/target/engine}}"
verify "$src" || { echo "sync-engine: $src/DesignEngine.xcframework does not match scripts/engine.pin" >&2; exit 1; }
rm -rf "$vendor"; mkdir -p "$vendor"
cp -R "$src/DesignEngine.xcframework" "$vendor/"
echo "sync-engine: DesignEngine @ $(grep '^CORE_COMMIT=' "$pin" | cut -d= -f2)"
