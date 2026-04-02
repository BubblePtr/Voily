APP_NAME := Voily
BUILD_DIR := .xcodebuild
APP_PATH := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app

.PHONY: build run install clean

build:
	xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug -derivedDataPath $(BUILD_DIR) build

run: build
	open "$(APP_PATH)"

install: build
	@mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	cp -R "$(APP_PATH)" "$(HOME)/Applications/$(APP_NAME).app"
	@echo "Installed to $(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf .build $(BUILD_DIR)
