#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"

pkill -f "$APP_PATH/Contents/MacOS/AbarNativeOverlay" 2>/dev/null || true
/usr/bin/xattr -cr "$APP_PATH" 2>/dev/null || true
open -n "$APP_PATH"
echo "[Abar] 已打开：$APP_PATH"
