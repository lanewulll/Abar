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
command -v swift >/dev/null || fail "未找到 Swift，请先安装 Xcode Command Line Tools。"
command -v xcode-select >/dev/null || fail "未找到 xcode-select。"

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(`.`)[0])')"
[[ "$NODE_MAJOR" -ge 20 ]] || fail "需要 Node.js 20 或更高版本。"

SWIFT_MAJOR="$(swift --version 2>&1 | sed -n 's/.*Apple Swift version \([0-9][0-9]*\).*/\1/p' | head -1)"
[[ -n "$SWIFT_MAJOR" && "$SWIFT_MAJOR" -ge 6 ]] || fail "需要 Swift 6 或更高版本。"

echo "环境检查通过：macOS $(/usr/bin/sw_vers -productVersion)，$(uname -m)，Node $(node --version)，Swift ${SWIFT_MAJOR}。"
