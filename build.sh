#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SimpleText"
BUNDLE_ID="com.simpletext.app"
VERSION="0.0.1.91"
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

# Copy SPM resource bundles (tree-sitter grammar query files used by Neon)
find -L "${BUILD_DIR}" -maxdepth 1 -name "*.bundle" -exec cp -R {} "${APP_DIR}/Resources/" \;

# Copy app icon
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "${APP_DIR}/Resources/AppIcon.icns"
else
    echo "WARNING: AppIcon.icns not found — app will build without an icon" >&2
fi

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
                <string>markdown</string>
                <string>swift</string>
                <string>py</string>
                <string>pyw</string>
                <string>js</string>
                <string>mjs</string>
                <string>cjs</string>
                <string>ts</string>
                <string>tsx</string>
                <string>json</string>
                <string>jsonc</string>
                <string>html</string>
                <string>htm</string>
                <string>css</string>
                <string>sh</string>
                <string>bash</string>
                <string>zsh</string>
                <string>go</string>
                <string>rs</string>
                <string>c</string>
                <string>h</string>
                <string>cpp</string>
                <string>cc</string>
                <string>cxx</string>
                <string>hpp</string>
                <string>hxx</string>
                <string>java</string>
                <string>rb</string>
                <string>yaml</string>
                <string>yml</string>
                <string>toml</string>
                <string>ps1</string>
                <string>psm1</string>
                <string>psd1</string>
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
