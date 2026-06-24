#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${ABAR_INSTALL_DIR:-$HOME/Applications}"

"$ROOT_DIR/scripts/check-env.sh"
npm --prefix "$ROOT_DIR" install
"$ROOT_DIR/scripts/install-app.sh"
open "$INSTALL_DIR/Abar.app"

echo
echo "Abar 已启动。下一步生成 Codex Hook 配置："
echo "  node reporters/codex-hook-reporter/install.js"
