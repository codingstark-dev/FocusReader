#!/bin/bash
set -e

echo "🔨 Building Focus Reader for Books..."

cd "$(dirname "$0")/FocusReader"
swift build -c release 2>&1

BINARY=".build/release/FocusReader"
APP_DIR="../FocusReaderApp/FocusReader.app"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/FocusReader"

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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
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

# Ad-hoc code sign so macOS will run it
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo ""
echo "✅ Build complete!"
echo "📦 App: $(cd .. && pwd)/FocusReaderApp/FocusReader.app"
echo ""
echo "To install:"
echo "  cp -r FocusReaderApp/FocusReader.app /Applications/"
echo ""
echo "To run now:"
echo "  open FocusReaderApp/FocusReader.app"
