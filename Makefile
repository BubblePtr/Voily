APP_NAME := Voily
INSTALL_DIR := $(HOME)/Applications/$(APP_NAME).app

.PHONY: build run install clean

build:
	xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug build

run: build
	open "$(INSTALL_DIR)"

install: build
	@echo "App is already built to $(INSTALL_DIR)"

clean:
	rm -rf .build
