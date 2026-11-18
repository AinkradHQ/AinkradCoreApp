# Ainkrad for Mac. The Xcode project is generated from project.yml by XcodeGen and is not committed.
ifneq ($(wildcard /Applications/Xcode.app),)
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
endif

SCHEME := AinkradCoreMac
PROJECT := AinkradCore.xcodeproj
APP := build/Build/Products/Debug/Ainkrad.app
PACKAGES := Packages/AinkradClient Packages/CoreUI Packages/CoreKit Packages/Features Packages/DesignCanvas
# Tokens.swift is generated (scripts/sync-tokens.sh) and not swift-format clean
FORMAT_PATHS := App Tests/UI Packages/CoreKit/Sources Packages/CoreKit/Tests $(filter-out %/Tokens.swift,$(shell find Packages/CoreUI Packages/Features Packages/DesignCanvas -name '*.swift' -not -path '*/.build/*'))

.DEFAULT_GOAL := generate
include scripts/guardrails.mk
.PHONY: dmg generate open build test uitest run lint format format-check sync-client sync-engine engine-check strings clean

generate: ## Generate the Xcode project from project.yml
	xcodegen generate --quiet

open: generate
	open $(PROJECT)

build: lint engine-check generate ## Debug build into ./build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath build -quiet build

test: lint engine-check ## Package tests (the app target has none yet)
	@for p in $(PACKAGES); do echo "swift test: $$p"; (cd $$p && swift test --quiet) || exit 1; done

uitest: generate ## Keyboard-path UI tests (take over the screen: wait for the shared lock and 5 idle minutes, UI_IDLE=0 to skip)
	scripts/ui-lock.sh caffeinate -d xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath build -quiet test

run: build
	open "$(APP)"

lint: format-check guard-bounce

format:
	swift format format -i --recursive --parallel $(FORMAT_PATHS)

format-check:
	swift format lint --strict --recursive --parallel $(FORMAT_PATHS)

engine-check: ## The vendored DesignEngine.xcframework matches scripts/engine.pin
	scripts/sync-engine.sh check

sync-engine: ## Vendor DesignEngine.xcframework from ../AinkradCore/target/engine (make engine there first)
	scripts/sync-engine.sh

sync-client: ## Re-vendor the generated client from ../AinkradCore
	scripts/sync-client.sh

strings: ## Copy the strings the last build extracted into the String Catalogs (run make build first)
	scripts/sync-strings.sh

clean:
	rm -rf build $(PROJECT)

dmg: ## Release .dmg in build/ (dry run: signs only when SIGN_IDENTITY and NOTARY_PROFILE are set; see scripts/release.sh)
	scripts/release.sh
