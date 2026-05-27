#!/bin/bash
set -e

# Usage: ./build.sh [path/to/logo.png]
# Environment Variables:
#   SIGN_IDENTITY: Custom codesign identity (defaults to ad-hoc "-")

echo "🔨 Building Focus Reader for Books..."

cd "$(dirname "$0")/FocusReader"

# Check if a logo PNG file is passed to compile the icon
LOGO_PNG="$1"
if [ -n "$LOGO_PNG" ]; then
    if [ ! -f "$LOGO_PNG" ]; then
        echo "❌ Logo file not found: $LOGO_PNG"
        exit 1
    fi
    echo "🎨 Generating AppIcon.icns from $LOGO_PNG..."
    ICONSET="AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    
    # Generate the various sizes required for macOS .icns
    sips -z 16 16     "$LOGO_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$LOGO_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$LOGO_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$LOGO_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$LOGO_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$LOGO_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$LOGO_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$LOGO_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$LOGO_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$LOGO_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    
    iconutil -c icns "$ICONSET"
    mv AppIcon.icns ../FocusReaderApp/AppIcon.icns
    rm -rf "$ICONSET"
    echo "✅ AppIcon.icns generated at FocusReaderApp/AppIcon.icns"
fi

swift build -c release 2>&1

BINARY=".build/release/FocusReader"
APP_DIR="../FocusReaderApp/FocusReader.app"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/FocusReader"

# Copy AppIcon.icns if it exists in FocusReaderApp
if [ -f "../FocusReaderApp/AppIcon.icns" ]; then
    echo "🎨 Copying AppIcon.icns to bundle..."
    cp "../FocusReaderApp/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FocusReader</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusreader.books</string>
    <key>CFBundleName</key>
    <string>Focus Reader</string>
    <key>CFBundleDisplayName</key>
    <string>Focus Reader for Books</string>
    <key>CFBundleVersion</key>
    <string>1.0.2</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Focus Reader needs Accessibility access to read text from the Books app and register the global ⌥⌘R keyboard shortcut.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Focus Reader for macOS Books</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

# Code Sign App
SIGN_IDENTITY="${SIGN_IDENTITY:-"-"}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️  Signing ad-hoc (unsigned/no identity). Gatekeeper will block public downloads."
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
else
    echo "✍️  Signing with identity: $SIGN_IDENTITY..."
    # Hardened runtime and timestamping are required for Apple notarization
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

# Verify codesign
echo "🔍 Verifying signature..."
codesign -vvv --deep --strict "$APP_DIR"

# Package into a DMG
DMG_PATH="../FocusReaderApp/FocusReader.dmg"
echo "💿 Packaging app into DMG: $DMG_PATH..."
rm -f "$DMG_PATH"

DMG_STAGE="../FocusReaderApp/dmg_stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

cp -r "$APP_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "Focus Reader Installer" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" > /dev/null
rm -rf "$DMG_STAGE"

echo ""
echo "✅ Build complete!"
echo "📦 App: $(cd .. && pwd)/FocusReaderApp/FocusReader.app"
echo "💿 DMG: $(cd .. && pwd)/FocusReaderApp/FocusReader.dmg"
echo ""
echo "To install:"
echo "  Drag Focus Reader from the DMG to Applications, or run:"
echo "  cp -r FocusReaderApp/FocusReader.app /Applications/"
echo ""
echo "To run now:"
echo "  open FocusReaderApp/FocusReader.app"
