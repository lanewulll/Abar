#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${ABAR_INSTALL_DIR:-$HOME/Applications}"

"$ROOT_DIR/scripts/check-env.sh"
npm --prefix "$ROOT_DIR" ci
"$ROOT_DIR/scripts/install-app.sh"
open "$INSTALL_DIR/Abar.app"

for _ in {1..20}; do
  if /usr/bin/curl --silent --max-time 1 "http://127.0.0.1:${ABAR_SERVER_PORT:-3987}/health" | grep -q '"service":"abar"'; then
    break
  fi
  sleep 0.25
done

echo
echo "Abar 已构建、安装并启动。setup 不会静默修改 Codex Hook。"
echo "下一步先预览，再由你明确执行安全合并："
echo "  npm run hooks:preview"
echo "  npm run hooks:install"
echo "随后必须在 Codex 中运行 /hooks，人工检查并信任 Abar Hook。"
