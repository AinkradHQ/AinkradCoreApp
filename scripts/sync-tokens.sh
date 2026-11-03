#!/bin/sh
# Re-copy the generated design tokens into CoreUI. Never hand-edit the copy.
# build.py regenerates Tokens.swift and gates contrast/drift: if it fails, nothing is copied.
set -eu
src="${DESIGN_SYSTEM:-$HOME/Home/Projects/Ainkrad/Designs/core/ds/system}"
(cd "$src" && python3 build.py)
cp "$src/Tokens.swift" "$(dirname "$0")/../Packages/CoreUI/Sources/CoreUI/Tokens.swift"
