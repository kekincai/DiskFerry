#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DiskFerry"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

# Quitting with pkill skips the app's "stop the copy?" prompt and would leave its rclone
# child running unattended, so refuse while a copy is in progress.
for pid in $(pgrep -x "$APP_NAME" || true); do
  if pgrep -P "$pid" -x rclone >/dev/null 2>&1; then
    echo "Disk Ferry 正在复制（rclone 运行中）。请先在应用里停止或等它完成，再重新构建。" >&2
    exit 1
  fi
done
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
"$ROOT_DIR/script/make_app_bundle.sh" "$BUILD_BINARY" "$APP_BUNDLE" "0.0.0-dev" "1"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--verify]" >&2
    exit 2
    ;;
esac
