#!/bin/sh
# Copies the Swift string literals the compiler extracted on the last `make build` into each module's String Catalog
# (xcodebuild fills the extraction data but, unlike the Xcode editor, does not write the catalogs). English is the source
# language; nothing is translated here. Run after `make build`, then review the catalog diff.
set -eu
cd "$(dirname "$0")/.."
OBJ=build/Build/Intermediates.noindex
sync() { # <catalog> <build dir>
	files=$(find "$2" -name '*.stringsdata' -path '*Objects-normal/arm64*' ! -name 'ExtractedAppShortcutsMetadata.stringsdata' ! -name 'GeneratedAssetSymbols.stringsdata')
	[ -n "$files" ] || { echo "no extraction data for $1: run make build first" >&2; exit 1; }
	# shellcheck disable=SC2086
	xcrun xcstringstool sync "$1" --stringsdata $files
	echo "synced $1"
}
sync Packages/CoreUI/Sources/CoreUI/Resources/Localizable.xcstrings "$OBJ/CoreUI.build/Debug/CoreUI-t.build"
for t in Shell Agents Terminals Admin Accounts Brain Pairing; do
	sync "Packages/Features/Sources/$t/Resources/Localizable.xcstrings" "$OBJ/Features.build/Debug/$t-t.build"
done
sync App/Mac/Localizable.xcstrings "$OBJ/AinkradCore.build/Debug/AinkradCoreMac.build"
