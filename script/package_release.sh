#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) release and packages it as .dmg and .zip.
# usage: package_release.sh <version> [build-number]
# Output: dist/release/DiskFerry-<version>.dmg, .zip and SHA256SUMS.txt
set -euo pipefail

VERSION="${1:?usage: package_release.sh <version> [build-number]}"
BUILD_NUMBER="${2:-1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/release"
STAGING="$OUT_DIR/staging"
APP="$STAGING/Disk Ferry.app"
NAME="DiskFerry-$VERSION"

cd "$ROOT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$STAGING"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
lipo -info "$BIN_DIR/DiskFerry"

"$ROOT_DIR/script/make_app_bundle.sh" "$BIN_DIR/DiskFerry" "$APP" "$VERSION" "$BUILD_NUMBER"
codesign --verify --deep --strict "$APP"

# zip: keeps the bundle's extended attributes and signature intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT_DIR/$NAME.zip"

# dmg: drag-to-Applications window.
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Disk Ferry $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$OUT_DIR/$NAME.dmg" >/dev/null
rm -rf "$STAGING"

(cd "$OUT_DIR" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt)
