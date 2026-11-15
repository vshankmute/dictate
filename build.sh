#!/bin/bash
# Builds Dictate.app from dictate.swift (uses whisper-cli from Homebrew or ~/Library/Application Support/Dictate).
# For a DMG with whisper-cli inside the app, run make-dmg.sh instead.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"

rm -rf Dictate.app
mkdir -p Dictate.app/Contents/MacOS Dictate.app/Contents/Resources
if [ -f AppIcon.icns ]; then cp AppIcon.icns Dictate.app/Contents/Resources/AppIcon.icns; fi
cat > Dictate.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Dictate</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>io.github.vshankmute.dictate</string>
    <key>CFBundleName</key><string>Dictate</string>
    <key>CFBundleDisplayName</key><string>Dictate</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 vshankmute. MIT License.</string>
    <key>NSMicrophoneUsageDescription</key><string>Dictate records your voice and transcribes it on this Mac.</string>
</dict>
</plist>
PLIST

# Explicit target = LSMinimumSystemVersion above. Without it swiftc can stamp a minimum macOS
# newer than the running one, and open fails with LaunchServices error -10825.
swiftc -parse-as-library -O -target "$(uname -m)-apple-macos14.0" dictate.swift -o Dictate.app/Contents/MacOS/Dictate
xattr -cr Dictate.app
codesign --force --sign - Dictate.app
echo "Built: $(pwd)/Dictate.app"
