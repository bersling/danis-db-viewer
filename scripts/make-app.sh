#!/bin/bash
# Packages the release build into dist/Dani's DB Viewer.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/Dani's DB Viewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DanisDBViewer "$APP/Contents/MacOS/DanisDBViewer"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DanisDBViewer</string>
    <key>CFBundleIdentifier</key><string>com.danis.dbviewer</string>
    <key>CFBundleName</key><string>Dani's DB Viewer</string>
    <key>CFBundleDisplayName</key><string>Dani's DB Viewer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP"
