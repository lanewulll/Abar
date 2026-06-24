#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${ABAR_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/Abar.app"

pkill -f "$TARGET_APP/Contents/MacOS/AbarNativeOverlay" 2>/dev/null || true
rm -rf "$TARGET_APP"

echo "Abar 应用已移除：$TARGET_APP"
echo "本地数据仍保留在：$HOME/Library/Application Support/abar"
