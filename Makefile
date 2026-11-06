CONFIG ?= release
VERSION = 0.1.1
APP = build/MD Stickies.app
BIN = .build/$(CONFIG)/StickiesMD

.PHONY: build test app bundle run snapshot icon docs release clean

build:
	swift build -c $(CONFIG)

test:
	swift test

app: build bundle

bundle:
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BIN) "$(APP)/Contents/MacOS/StickiesMD"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)"

run: app
	open "$(APP)"

# Renders sample notes to build/snapshots/*.png (no windows shown).
snapshot: app
	"$(APP)/Contents/MacOS/StickiesMD" --snapshot build/snapshots

# Redraws Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

# The README's images.
docs: icon snapshot
	cp build/AppIcon.iconset/icon_128x128@2x.png docs/icon.png
	cp build/snapshots/preview.png docs/preview.png

# Two zips for a GitHub release, one per kind of Mac.
release:
	swift build -c release --arch arm64
	$(MAKE) bundle BIN=.build/arm64-apple-macosx/release/StickiesMD 'APP=build/arm64/MD Stickies.app'
	ditto -c -k --keepParent "build/arm64/MD Stickies.app" build/StickiesMD-$(VERSION)-AppleSilicon.zip
	swift build -c release --arch x86_64
	$(MAKE) bundle BIN=.build/x86_64-apple-macosx/release/StickiesMD 'APP=build/x86_64/MD Stickies.app'
	ditto -c -k --keepParent "build/x86_64/MD Stickies.app" build/StickiesMD-$(VERSION)-Intel.zip

clean:
	rm -rf .build build
