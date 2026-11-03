# Ainkrad Core for Mac. The Xcode project is generated from project.yml by XcodeGen and is not committed.
ifneq ($(wildcard /Applications/Xcode.app),)
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
endif

SCHEME := AinkradCoreMac
PROJECT := AinkradCore.xcodeproj
APP := build/Build/Products/Debug/Ainkrad Core.app
PACKAGES := Packages/AinkradClient Packages/CoreUI Packages/Features
# Tokens.swift is generated (scripts/sync-tokens.sh) and not swift-format clean
FORMAT_PATHS := App $(filter-out %/Tokens.swift,$(shell find Packages/CoreUI Packages/Features -name '*.swift' -not -path '*/.build/*'))

.DEFAULT_GOAL := generate
.PHONY: generate open build test run lint format format-check sync-client clean

generate: ## Generate the Xcode project from project.yml
	xcodegen generate --quiet

open: generate
	open $(PROJECT)

build: lint generate ## Debug build into ./build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath build -quiet build

test: lint ## Package tests (the app target has none yet)
	@for p in $(PACKAGES); do echo "swift test: $$p"; (cd $$p && swift test --quiet) || exit 1; done

run: build
	open "$(APP)"

lint: format-check

format:
	swift format format -i --recursive --parallel $(FORMAT_PATHS)

format-check:
	swift format lint --strict --recursive --parallel $(FORMAT_PATHS)

sync-client: ## Re-vendor the generated client from ../AinkradCore
	scripts/sync-client.sh

clean:
	rm -rf build $(PROJECT)
