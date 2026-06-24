# Abar

<p align="center">
  <img src="docs/images/abar-icon.png" width="180" alt="Abar 应用图标">
</p>

<p align="center">
  一个专为 OpenAI Codex 设计的原生 macOS 顶部悬浮监视器。
</p>

Abar 常驻屏幕顶部和菜单栏，用于查看 Codex 的额度、任务活动、连接来源与本地 Skill。悬停时面板会展开；点击任务可以尝试跳回对应的 Codex 会话。

> 当前版本只提供源码构建，不提供已签名、公证的 GitHub Release 安装包。

## 功能

- 原生 Swift、SwiftUI 与 AppKit 实现，不依赖 Electron
- 显示 Codex 5 小时和每周额度
- 通过本地 Hook 展示正在运行和最近完成的任务
- 扫描项目及用户目录中的 `SKILL.md`
- 菜单栏状态指示：空闲、运行中和中断
- 本地 SQLite 存储，敏感字段写入前会被清理
- 本地事件服务只监听 `127.0.0.1`

## 系统要求

- Apple Silicon Mac（M1 或更新机型）
- macOS 14 Sonoma 或更高版本
- Node.js 20 或更高版本
- Swift 6 / Xcode Command Line Tools
- 已安装并登录 OpenAI Codex

目前不支持 Intel Mac。

## 快速安装

### 1. 克隆并安装

```bash
git clone https://github.com/lanewulll/Abar.git
cd Abar
npm run setup
```

`npm run setup` 会完成环境检查、构建应用、安装到 `~/Applications/Abar.app` 并启动。整个过程不需要 `sudo`。

如果只想检查环境：

```bash
npm run check
```

### 2. 生成 Codex Hook 配置

```bash
node reporters/codex-hook-reporter/install.js
```

命令会输出一段 JSON。请将其中的 `hooks` 合并到 `~/.codex/hooks.json`，不要直接覆盖已有 Hook。

输出大致如下，实际绝对路径以你的仓库位置为准：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "ABAR_SERVER_PORT=3987 node '/绝对路径/reporter.js'",
            "timeout": 2
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "ABAR_SERVER_PORT=3987 node '/绝对路径/reporter.js'",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

### 3. 在 Codex 中信任 Hook

1. 打开 Codex。
2. 输入 `/hooks`。
3. 检查并手动信任 Abar 的 Hook。
4. 新建一个任务，观察 Abar 面板是否出现任务记录。

Codex 的 Hook 信任步骤不能由 Abar 静默绕过。

## 使用

启动：

```bash
open ~/Applications/Abar.app
```

更新源码后重新安装：

```bash
git pull
npm run setup
```

退出 Abar：右键菜单栏中的 Abar 图标，选择 `Quit Abar`。

卸载应用：

```bash
npm run uninstall:app
```

卸载命令默认保留本地数据。如需彻底清理，可手动删除：

```bash
rm -rf "$HOME/Library/Application Support/abar"
rm -rf "$HOME/Library/Logs/Abar"
```

## 配置

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ABAR_SERVER_PORT` | `3987` | Abar 与 Reporter 使用的本地端口 |
| `ABAR_REPORTER_TIMEOUT_MS` | `800` | Reporter 请求超时时间 |
| `ABAR_REPORTER_DEBUG` | 未启用 | 设为 `1` 时写入轻量连接日志 |
| `ABAR_NATIVE_DB_PATH` | 应用数据目录 | 覆盖 SQLite 路径，主要用于开发和测试 |
| `ABAR_INSTALL_DIR` | `~/Applications` | 覆盖本地安装目录 |

如果修改端口，应用与 Hook 必须使用相同值。建议从终端启动自定义端口：

```bash
ABAR_SERVER_PORT=4567 "$HOME/Applications/Abar.app/Contents/MacOS/AbarNativeOverlay"
ABAR_SERVER_PORT=4567 node reporters/codex-hook-reporter/install.js
```

## 数据与隐私

Abar 的数据保存在：

```text
~/Library/Application Support/abar/abar.sqlite
```

Reporter 只向 `127.0.0.1` 发送 Hook 数据。Abar 会在写入数据库前清理名称中含有 `authorization`、`password`、`secret`、`token` 或 `api_key` 的字段。

额度功能会读取 `$CODEX_HOME/auth.json` 或 `~/.codex/auth.json` 中的本地 Codex 登录状态，并请求：

```text
https://chatgpt.com/backend-api/wham/usage
```

Abar 不会把访问令牌、刷新令牌、Cookie 或 Authorization Header 写入日志或数据库。额度快照只保存整理后的比例、重置时间和错误信息。

`wham/usage` 是 ChatGPT 的内部接口，不是稳定的公开 API，可能随时失效。官方额度页面是：

<https://chatgpt.com/codex/settings/usage>

## 故障排查

先运行自动诊断：

```bash
npm run doctor
```

诊断命令会检查应用安装、Hook 配置、端口、健康接口和 Codex 登录文件，但不会读取或输出令牌。

### 面板没有任务

- 确认 Abar 正在运行。
- 在 Codex 中运行 `/hooks`，确认 Hook 已启用和信任。
- 重新运行 Hook 生成器，并检查其中的 Reporter 路径是否仍然存在。
- 检查健康接口：

```bash
curl http://127.0.0.1:3987/health
```

正常响应为：

```json
{"ok":true,"service":"abar"}
```

### 端口被占用

```bash
lsof -nP -iTCP:3987 -sTCP:LISTEN
```

退出占用该端口的程序，或为 Abar 与 Hook 同时配置另一个端口。Abar 的启动日志会记录 `server bind failed`。

### 看不到额度

- 确认 Codex 已登录。
- 检查 `~/.codex/auth.json` 是否存在。
- 网络、代理、令牌失效、限流或内部接口变化都会导致刷新失败。
- Abar 会在面板中显示最近一次额度刷新错误。

### macOS 阻止打开

本地构建的应用使用 ad-hoc 签名，没有 Apple Developer ID 签名，也没有经过公证。通过本仓库源码执行 `npm run setup` 后，脚本会清理本地隔离属性；不要运行来源不明的 Abar 二进制文件。

### Reporter 日志

在 `~/.codex/hooks.json` 的 Reporter 命令开头添加 `ABAR_REPORTER_DEBUG=1`。例如：

```text
ABAR_REPORTER_DEBUG=1 ABAR_SERVER_PORT=3987 node '/绝对路径/reporter.js'
```

日志位于：

```text
~/Library/Logs/Abar/codex-hook-reporter.log
```

## 开发

```bash
npm install
npm test
npm run dev
```

构建 release 应用：

```bash
npm run build
```

产物位于：

```text
native-overlay/dist/Abar.app
```

核心目录：

```text
native-overlay/
  Sources/                 Swift 核心与 macOS 应用
  Tests/                   Swift 测试
  scripts/                 应用构建与启动脚本
reporters/
  codex-hook-reporter/     Codex Hook Reporter
scripts/                   环境检查、安装和卸载
docs/images/               项目图像资源
.github/                   CI 与协作模板
```

## 已知限制

- 只支持 Codex，不支持 Claude、Cursor、Ollama 或多 Agent 聚合。
- 只支持 Apple Silicon 和 macOS 14 以上版本。
- 当前不提供自动启动、自动更新、DMG、签名或公证。
- Abar 无法可靠判断 Codex 当前正在使用的确切 Skill，只能展示扫描结果。
- 额度依赖未公开的 ChatGPT 内部接口。

## 参与贡献

提交 Issue 或 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按照 [SECURITY.md](SECURITY.md) 私下报告。

## 许可证

[MIT](LICENSE)
