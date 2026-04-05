APP_NAME := Voily
BUILD_DIR := .xcodebuild
APP_PATH := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app

.PHONY: build test run install clean

build:
	xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug -derivedDataPath $(BUILD_DIR) build

test:
	xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug -derivedDataPath $(BUILD_DIR) test

run: build
	open "$(APP_PATH)"

install: build
	@mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	cp -R "$(APP_PATH)" "$(HOME)/Applications/$(APP_NAME).app"
	@echo "Installed to $(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR)
