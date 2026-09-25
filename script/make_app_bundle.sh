#!/usr/bin/env bash
# Wraps a built DiskFerry binary into a signed (ad-hoc by default) .app bundle.
# usage: make_app_bundle.sh <binary> <output.app> [version] [build-number]
set -euo pipefail

BINARY="$1"
APP_BUNDLE="$2"
VERSION="${3:-0.0.0-dev}"
BUILD_NUMBER="${4:-1}"
APP_NAME="DiskFerry"
BUNDLE_ID="com.local.DiskFerry"
MIN_SYSTEM_VERSION="13.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENTS="$APP_BUNDLE/Contents"

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"

/usr/bin/swift "$ROOT_DIR/script/generate_app_icon.swift" "$ROOT_DIR"
cp "$ROOT_DIR/dist/DiskFerry.icns" "$CONTENTS/Resources/DiskFerry.icns"

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>DiskFerry</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Disk Ferry</string>
  <key>CFBundleDisplayName</key>
  <string>Disk Ferry</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key>
  <string>MIT License</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc ("-") unless SIGN_IDENTITY names a Developer ID certificate.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
