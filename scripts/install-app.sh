#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${ABAR_INSTALL_DIR:-$HOME/Applications}"
SOURCE_APP="$ROOT_DIR/native-overlay/dist/Abar.app"
TARGET_APP="$INSTALL_DIR/Abar.app"

"$ROOT_DIR/scripts/check-env.sh"
npm --prefix "$ROOT_DIR" run build

mkdir -p "$INSTALL_DIR"
pkill -f "$TARGET_APP/Contents/MacOS/AbarNativeOverlay" 2>/dev/null || true
rm -rf "$TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
/usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true

echo "Abar 已安装到：$TARGET_APP"
echo "运行：open \"$TARGET_APP\""
