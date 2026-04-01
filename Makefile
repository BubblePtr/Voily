APP_NAME := Voily
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
EXECUTABLE := $(BUILD_DIR)/$(APP_NAME)
INSTALL_DIR := $(HOME)/Applications/$(APP_NAME).app

.PHONY: build run install clean

build:
	swift build -c release
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(EXECUTABLE)" "$(MACOS_DIR)/$(APP_NAME)"
	cp "Config/Info.plist" "$(CONTENTS_DIR)/Info.plist"
	codesign --force --sign - "$(APP_DIR)"

run: build
	open "$(APP_DIR)"

install: build
	rm -rf "$(INSTALL_DIR)"
	mkdir -p "$(HOME)/Applications"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)"
	codesign --force --sign - "$(INSTALL_DIR)"

clean:
	rm -rf .build
