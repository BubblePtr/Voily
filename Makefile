APP_NAME := Voily
BUILD_DIR := .xcodebuild
APP_PATH := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app
RELEASE_SCRIPT := ./scripts/release.sh

.PHONY: build test test-logic test-app run install clean release archive export-app package-zip package-dmg notarize staple verify-release clean-release

build:
	xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug -derivedDataPath $(BUILD_DIR) build

test: test-logic test-app

test-logic:
	swift test

test-app:
	xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug -derivedDataPath $(BUILD_DIR) test

run: build
	open "$(APP_PATH)"

install: build
	@mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	cp -R "$(APP_PATH)" "$(HOME)/Applications/$(APP_NAME).app"
	@echo "Installed to $(HOME)/Applications/$(APP_NAME).app"

release archive export-app:
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
