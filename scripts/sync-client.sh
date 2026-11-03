#!/bin/sh
# Copies the generated Swift client from an AinkradCore checkout into Packages/AinkradClient
# and records the Core commit it came from. SwiftPM cannot depend on a sub-folder of a repo (plan D4).
# Usage: scripts/sync-client.sh [path-to-AinkradCore]   (default: ../AinkradCore)
set -eu
core="${1:-$(dirname "$0")/../../AinkradCore}"
src="$core/clients/swift"
dst="$(dirname "$0")/../Packages/AinkradClient"
[ -f "$src/Package.swift" ] || { echo "sync-client: no client at $src" >&2; exit 1; }
if [ -n "$(git -C "$core" status --porcelain -- clients/swift)" ]; then
  echo "sync-client: $src has uncommitted changes; commit them in AinkradCore first" >&2; exit 1
fi
rm -rf "$dst"; mkdir -p "$dst"
rsync -a --exclude .build --exclude .swiftpm "$src/" "$dst/"
git -C "$core" rev-parse HEAD > "$dst/CORE_COMMIT"
echo "sync-client: AinkradClient @ $(cat "$dst/CORE_COMMIT")"
