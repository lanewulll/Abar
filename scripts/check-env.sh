#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "错误：$1" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Abar 仅支持 macOS。"
[[ "$(uname -m)" == "arm64" ]] || fail "Abar 当前仅支持 Apple Silicon（M1 及更新机型）。"

MACOS_MAJOR="$(/usr/bin/sw_vers -productVersion | cut -d. -f1)"
[[ "$MACOS_MAJOR" -ge 14 ]] || fail "需要 macOS 14 或更高版本。"

command -v node >/dev/null || fail "未找到 Node.js，请安装 Node.js 20 或更高版本。"
command -v npm >/dev/null || fail "未找到 npm。"
command -v git >/dev/null || fail "未找到 Git。请先安装 Xcode Command Line Tools。"
command -v swift >/dev/null || fail "未找到 Swift，请先安装 Xcode Command Line Tools。"
command -v xcode-select >/dev/null || fail "未找到 xcode-select。"
/usr/bin/xcode-select -p >/dev/null 2>&1 || fail "Xcode Command Line Tools 尚未配置，请运行 xcode-select --install 并完成人工安装。"

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(`.`)[0])')"
[[ "$NODE_MAJOR" -ge 20 ]] || fail "需要 Node.js 20 或更高版本。"

SWIFT_MAJOR="$(swift --version 2>&1 | sed -n 's/.*Apple Swift version \([0-9][0-9]*\).*/\1/p' | head -1)"
[[ -n "$SWIFT_MAJOR" && "$SWIFT_MAJOR" -ge 6 ]] || fail "需要 Swift 6 或更高版本。"

if [[ "${ABAR_SKIP_CODEX_CHECK:-0}" != "1" ]]; then
  command -v codex >/dev/null || fail "未找到 Codex CLI。请先安装 OpenAI Codex。"
  codex login status >/dev/null 2>&1 || fail "Codex 尚未登录。请运行 codex login，并在浏览器中完成人工登录。"
fi

echo "环境检查通过：macOS $(/usr/bin/sw_vers -productVersion)，$(uname -m)，Node $(node --version)，Swift ${SWIFT_MAJOR}。"
