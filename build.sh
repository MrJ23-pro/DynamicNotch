#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=DynamicNotch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -wmo -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  DynamicNotch.swift -o "$APP/Contents/MacOS/DynamicNotch"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.local.dynamicnotch</string>
  <key>CFBundleName</key><string>DynamicNotch</string>
  <key>CFBundleExecutable</key><string>DynamicNotch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>DynamicNotch lit la musique en cours et contrôle la lecture dans Spotify.</string>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
echo "built $APP"
