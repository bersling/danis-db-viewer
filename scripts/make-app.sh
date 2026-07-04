#!/bin/bash
# Packages the release build into dist/Dani's DB Viewer.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/Dani's DB Viewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DanisDBViewer "$APP/Contents/MacOS/DanisDBViewer"

# App icon (regenerate if missing)
if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DanisDBViewer</string>
    <key>CFBundleIdentifier</key><string>com.danis.dbviewer</string>
    <key>CFBundleName</key><string>Dani's DB Viewer</string>
    <key>CFBundleDisplayName</key><string>Dani's DB Viewer</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

# Install into /Applications so Spotlight/Launchpad find it and the icon registers.
if [ "${DDV_INSTALL:-1}" = "1" ]; then
    DEST="/Applications/Dani's DB Viewer.app"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # Nudge Launch Services to pick up the new icon/bundle.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$DEST" >/dev/null 2>&1 || true
    touch "$DEST"
    echo "Installed: $DEST"

    # 'ddv' launcher next to the user's other CLI tools (where diffy lives).
    BINDIR="$HOME/.local/bin"
    mkdir -p "$BINDIR"
    cat > "$BINDIR/ddv" <<'LAUNCH'
#!/bin/bash
# Open Dani's DB Viewer. Any argument is treated as a SQLite file to add/open.
APP="/Applications/Dani's DB Viewer.app"
[ -d "$APP" ] || APP="$(cd "$(dirname "$0")" && pwd)/../dist/Dani's DB Viewer.app"
if [ $# -gt 0 ] && [ -f "$1" ]; then
    open -a "$APP" "$1"
else
    open -a "$APP"
fi
LAUNCH
    chmod +x "$BINDIR/ddv"
    echo "Launcher: $BINDIR/ddv  (run 'ddv' to open the app)"
fi
