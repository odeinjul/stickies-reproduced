CONFIG ?= release
APP = build/StickiesMD.app
BIN = .build/$(CONFIG)/StickiesMD

.PHONY: build test app run snapshot icon clean

build:
	swift build -c $(CONFIG)

test:
	swift test

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/StickiesMD
	mkdir -p $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)

run: app
	open $(APP)

# Renders sample notes to build/snapshots/*.png (no windows shown).
snapshot: app
	$(APP)/Contents/MacOS/StickiesMD --snapshot build/snapshots

# Redraws Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
