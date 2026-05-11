APP_NAME := Voily
PROJECT := Voily.xcodeproj
SCHEME := Voily
BUILD_DIR := .xcodebuild
APP_PATH := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app
RELEASE_SCRIPT := ./scripts/release.sh
XCODEGEN := xcodegen
XCODEBUILD := xcodebuild
SWIFT := swift

.PHONY: generate build test test-core test-logic test-app swift-build run install install-user install-system clean release archive export-app package-zip package-dmg notarize staple verify-release clean-release

generate:
	@command -v $(XCODEGEN) >/dev/null 2>&1 || { echo "Missing required command: $(XCODEGEN). Install XcodeGen before building Voily."; exit 1; }
	$(XCODEGEN) generate

swift-build:
	$(SWIFT) build

build: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) build

test: test-core test-app

test-core:
	$(SWIFT) test

test-logic: test-core

test-app: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) test

run: build
	open "$(APP_PATH)"

install: install-user

install-user: build
	@mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	cp -R "$(APP_PATH)" "$(HOME)/Applications/$(APP_NAME).app"
	@echo "Installed to $(HOME)/Applications/$(APP_NAME).app"

install-system: build
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_PATH)" "/Applications/$(APP_NAME).app"
	@echo "Installed to /Applications/$(APP_NAME).app"

release archive export-app: generate
	$(RELEASE_SCRIPT) archive

package-zip:
	$(RELEASE_SCRIPT) package-zip

package-dmg:
	$(RELEASE_SCRIPT) package-dmg

notarize:
	$(RELEASE_SCRIPT) notarize "$(ARTIFACT)"

staple:
	$(RELEASE_SCRIPT) staple "$(ARTIFACT)"

verify-release:
	$(RELEASE_SCRIPT) verify "$(ARTIFACT)"

clean-release:
	rm -rf build/release

clean:
	rm -rf $(BUILD_DIR)
	$(SWIFT) package clean
