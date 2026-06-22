#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"

pkill -f "AbarNativeOverlay" 2>/dev/null || true
open "$APP_PATH"
echo "[AbarNativeOverlay] opened: $APP_PATH"
