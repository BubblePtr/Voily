APP_NAME := Voily
APP_BUNDLE_ID := dev.kieranzhang.voily
PROJECT := Voily.xcodeproj
SCHEME := Voily
BUILD_DIR := .xcodebuild
DEBUG_APP_PATH := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP_PATH := build/release/$(APP_NAME).app
INSTALL_PATH := /Applications/$(APP_NAME).app
RELEASE_SCRIPT := ./scripts/release.sh
TCCUTIL := /usr/bin/tccutil
XCODEGEN := xcodegen
XCODEBUILD := xcodebuild
SWIFT := swift

.PHONY: generate build test test-core test-logic test-app swift-build run install-dev install-debug reset-permissions test-permission-flow clean release archive export-app package-zip package-dmg notarize staple verify-release clean-release

define install_app
	@set -e; \
	tmp_path="$(INSTALL_PATH).tmp"; \
	backup_path="$(INSTALL_PATH).backup"; \
	restore_backup() { \
		status=$$?; \
		set +e; \
		if [ $$status -ne 0 ] && [ -e "$$backup_path" ] && [ ! -e "$(INSTALL_PATH)" ]; then mv "$$backup_path" "$(INSTALL_PATH)"; fi; \
		rm -rf "$$tmp_path"; \
		exit $$status; \
	}; \
	trap restore_backup EXIT; \
	rm -rf "$$tmp_path" "$$backup_path"; \
	cp -R "$(1)" "$$tmp_path"; \
	if [ -e "$(INSTALL_PATH)" ]; then mv "$(INSTALL_PATH)" "$$backup_path"; fi; \
	mv "$$tmp_path" "$(INSTALL_PATH)"; \
	rm -rf "$$backup_path"; \
	trap - EXIT
endef

define reset_tcc_service
	@output=$$($(TCCUTIL) reset $(1) "$(APP_BUNDLE_ID)" 2>&1); status=$$?; \
	if [ $$status -ne 0 ]; then \
		if printf "%s\n" "$$output" | grep -q "No such bundle identifier"; then \
			echo "No existing $(1) TCC grant found for $(APP_BUNDLE_ID); continuing."; \
		else \
			echo "$$output"; \
			echo "Failed to reset $(1) permission for $(APP_BUNDLE_ID). Run this target from the macOS user account that owns the permission grant."; \
			exit $$status; \
		fi; \
	elif [ -n "$$output" ]; then \
		echo "$$output"; \
	fi
endef

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
	open "$(DEBUG_APP_PATH)"

install-dev: release
	$(call install_app,$(RELEASE_APP_PATH))
	@echo "Installed Developer ID development build to $(INSTALL_PATH)"

install-debug: build
	$(call install_app,$(DEBUG_APP_PATH))
	@echo "Installed Debug build to $(INSTALL_PATH)"

reset-permissions:
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	$(call reset_tcc_service,Microphone)
	$(call reset_tcc_service,Accessibility)

test-permission-flow:
	$(MAKE) reset-permissions
	$(MAKE) install-debug
	open -n "$(INSTALL_PATH)"
	@echo "Installed Debug build to $(INSTALL_PATH) with Microphone and Accessibility permissions reset for $(APP_BUNDLE_ID)"

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
