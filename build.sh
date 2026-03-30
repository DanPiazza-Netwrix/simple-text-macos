#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SimpleText"
BUNDLE_ID="com.simpletext.app"
VERSION="0.0.1.44"
MIN_MACOS="13.0"

BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app/Contents"

echo "Building ${APP_NAME}..."
swift build -c release

echo "Assembling ${APP_NAME}.app..."
rm -rf "build/${APP_NAME}.app"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/MacOS/${APP_NAME}"

# Copy app icon
cp AppIcon.icns "${APP_DIR}/Resources/AppIcon.icns" 2>/dev/null || true

# Write Info.plist
cat > "${APP_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>txt</string>
                <string>md</string>
                <string>swift</string>
                <string>py</string>
                <string>js</string>
                <string>ts</string>
                <string>json</string>
                <string>yaml</string>
                <string>yml</string>
                <string>toml</string>
                <string>sh</string>
                <string>log</string>
                <string>csv</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Plain Text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Done: build/${APP_NAME}.app"
echo "Run:  open build/${APP_NAME}.app"
