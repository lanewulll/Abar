#!/usr/bin/env bash
set -uo pipefail

PORT="${ABAR_SERVER_PORT:-3987}"
INSTALL_DIR="${ABAR_INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/Abar.app"
HOOKS_PATH="${CODEX_HOME:-$HOME/.codex}/hooks.json"
AUTH_PATH="${CODEX_HOME:-$HOME/.codex}/auth.json"
issues=0

ok() {
  echo "✓ $1"
}

warn() {
  echo "✗ $1"
  issues=$((issues + 1))
}

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  warn "ABAR_SERVER_PORT 无效：${PORT}"
  PORT=3987
fi

if [[ -d "$APP_PATH" ]]; then
  ok "应用已安装：${APP_PATH}"
else
  warn "未找到 ${APP_PATH}，请运行 npm run setup"
fi

if [[ -f "$HOOKS_PATH" ]] && grep -q "codex-hook-reporter/reporter.js" "$HOOKS_PATH"; then
  ok "已在 ${HOOKS_PATH} 中找到 Abar Hook"
else
  warn "未检测到 Abar Hook，请运行 node reporters/codex-hook-reporter/install.js 并手动合并"
fi

HEALTH="$(curl --silent --max-time 1 "http://127.0.0.1:${PORT}/health" 2>/dev/null || true)"
if [[ "$HEALTH" == *'"service":"abar"'* ]]; then
  ok "Abar 本地服务正在监听 127.0.0.1:${PORT}"
elif /usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  warn "端口 ${PORT} 已被其他进程占用"
  /usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sed -n '1,3p'
else
  warn "Abar 本地服务未运行，请执行 open \"${APP_PATH}\""
fi

if [[ -f "$AUTH_PATH" ]]; then
  ok "已找到 Codex 登录文件：${AUTH_PATH}"
else
  warn "未找到 Codex 登录文件：${AUTH_PATH}；额度功能将不可用"
fi

if (( issues > 0 )); then
  echo
  echo "诊断完成：发现 ${issues} 项需要处理。"
  exit 1
fi

echo
echo "诊断完成：未发现问题。"
