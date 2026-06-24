<p align="center">
  <img src="docs/images/abar-banner.svg" width="100%" alt="ABAR — Codex Activity, Quota and Skills">
</p>

# Abar

> 一个专为 OpenAI Codex 设计的原生 macOS 顶部悬浮监视器。

<p align="center">
  <a href="https://github.com/lanewulll/Abar/actions/workflows/ci.yml"><img src="https://github.com/lanewulll/Abar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="#系统要求"><img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="#系统要求"><img src="https://img.shields.io/badge/Apple%20Silicon-arm64-37e58c" alt="Apple Silicon"></a>
  <a href="#开发"><img src="https://img.shields.io/badge/Swift-6-ff765f?logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="https://openai.com/codex/"><img src="https://img.shields.io/badge/OpenAI-Codex-111111?logo=openai&logoColor=white" alt="OpenAI Codex"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-37e58c" alt="MIT License"></a>
  <a href="#快速开始"><img src="https://img.shields.io/badge/文档-中文-ff765f" alt="中文文档"></a>
</p>

Abar 常驻屏幕顶部与菜单栏，把 Codex 的额度、任务活动、连接来源和本地 Skill 放在一个随时可见的原生面板里。悬停即可展开，任务完成后保留当日记录，点击任务还能尝试跳回对应的 Codex 会话。

它由 Swift、SwiftUI 与 AppKit 构建，不依赖 Electron；Hook 事件和快照保存在本地 SQLite 中，事件服务只监听 `127.0.0.1`。这是一个面向源码构建的早期项目：当前不提供签名、公证的二进制 Release。

| 能力 | Abar 如何工作 |
| --- | --- |
| **原生顶部悬浮** | 使用无边框 `NSPanel` 常驻屏幕顶部，收起时保持轻量，悬停后展开完整面板。 |
| **额度一览** | 展示 Codex 5 小时与每周窗口的使用比例、剩余额度和重置时间。 |
| **任务追踪** | 通过 `UserPromptSubmit` 与 `Stop` Hook 显示运行中任务和当日最近完成记录。 |
| **跳回会话** | 点击已完成任务时优先打开 `codex://threads/...`，失败时回退到激活 Codex。 |
| **Skill 扫描** | 扫描项目、用户与系统位置中的 `SKILL.md`，汇总当前可用 Skill。 |
| **本地隐私** | Reporter 只连接本机；敏感字段写入数据库前会被清理，不持久化认证令牌。 |
| **源码安装** | 提供环境检查、构建、安装、诊断和卸载脚本，无需 `sudo`。 |

<p align="center">
  <img src="docs/images/abar-preview.png" alt="使用虚构任务与额度数据生成的 Abar 实际界面">
</p>

<p align="center"><sub>真实应用界面；截图仅使用虚构任务、虚构路径和公开 API 地址。</sub></p>

## 快速开始

### 系统要求

- Apple Silicon Mac（M1 或更新机型）
- macOS 14 Sonoma 或更高版本
- Node.js 20 或更高版本
- Swift 6 / Xcode Command Line Tools
- 已安装并登录 OpenAI Codex

目前不支持 Intel Mac。

### 1. 克隆并安装

```bash
git clone https://github.com/lanewulll/Abar.git
cd Abar
npm run setup
```

`npm run setup` 会检查环境、构建应用、安装到 `~/Applications/Abar.app` 并启动，全程不需要 `sudo`。

### 2. 配置 Codex Hook

```bash
node reporters/codex-hook-reporter/install.js
```

将输出的 `hooks` 合并到 `~/.codex/hooks.json`，不要覆盖已有配置。随后在 Codex 中输入 `/hooks`，检查并手动信任 Abar 的 `UserPromptSubmit` 与 `Stop` Hook。

### 3. 验证连接

在 Codex 中新建一个任务，悬停屏幕顶部的 Abar 面板；或直接检查健康接口：

```bash
curl http://127.0.0.1:3987/health
```

正常响应：

```json
{"ok":true,"service":"abar"}
```

## Hook 配置

Hook 生成器会写入 Reporter 的绝对路径，因此移动或重新克隆仓库后需要重新生成配置。Codex 的 Hook 信任步骤不能由 Abar 静默绕过。

<details>
<summary><strong>查看 Hook 配置结构</strong></summary>

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

实际路径以生成器输出为准。

</details>

## 工作原理

1. Codex 在提交提示词和任务停止时执行本地 Reporter。
2. Reporter 从标准输入读取 Hook JSON，并以非阻塞方式发送到 `127.0.0.1`。
3. Abar 清理敏感字段，将事件、额度和 Skill 快照写入本地 SQLite。
4. 原生面板读取快照，推导任务状态、菜单栏信号和会话跳转目标。

Reporter 在 Abar 未运行、请求超时或输入无效时仍以成功状态退出，监控功能不会阻塞 Codex。

## 配置

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ABAR_SERVER_PORT` | `3987` | Abar 与 Reporter 共用的本地端口 |
| `ABAR_REPORTER_TIMEOUT_MS` | `800` | Reporter 请求超时，单位为毫秒 |
| `ABAR_REPORTER_DEBUG` | 未启用 | 设为 `1` 时记录轻量连接错误 |
| `ABAR_NATIVE_DB_PATH` | 应用数据目录 | 覆盖 SQLite 路径，主要用于开发和测试 |
| `ABAR_INSTALL_DIR` | `~/Applications` | 覆盖本地安装目录 |

<details>
<summary><strong>自定义端口、调试日志与更新卸载</strong></summary>

应用与 Hook 必须使用相同端口：

```bash
ABAR_SERVER_PORT=4567 "$HOME/Applications/Abar.app/Contents/MacOS/AbarNativeOverlay"
ABAR_SERVER_PORT=4567 node reporters/codex-hook-reporter/install.js
```

在 Hook 命令开头添加调试变量：

```text
ABAR_REPORTER_DEBUG=1 ABAR_SERVER_PORT=3987 node '/绝对路径/reporter.js'
```

日志位于：

```text
~/Library/Logs/Abar/codex-hook-reporter.log
```

更新：

```bash
git pull
npm run setup
```

卸载应用但保留数据：

```bash
npm run uninstall:app
```

彻底清理本地数据：

```bash
rm -rf "$HOME/Library/Application Support/abar"
rm -rf "$HOME/Library/Logs/Abar"
```

</details>

## 数据与隐私

本地数据库位于：

```text
~/Library/Application Support/abar/abar.sqlite
```

Reporter 只向 `127.0.0.1` 发送数据。Abar 会在写入前清理名称中含有 `authorization`、`password`、`secret`、`token` 或 `api_key` 的字段。

额度功能会读取 `$CODEX_HOME/auth.json` 或 `~/.codex/auth.json` 中的本地登录状态，并请求：

```text
https://chatgpt.com/backend-api/wham/usage
```

Abar 不会将访问令牌、刷新令牌、Cookie 或 Authorization Header 写入日志或数据库，只保存整理后的额度比例、重置时间和错误信息。

> `wham/usage` 是 ChatGPT 的内部接口，不是稳定的公开 API，可能随时变化。官方额度页面是 <https://chatgpt.com/codex/settings/usage>。

## 故障排查

先运行自动诊断：

```bash
npm run doctor
```

诊断命令会检查应用安装、Hook 配置、端口、健康接口和 Codex 登录文件，但不会读取或输出令牌。

<details>
<summary><strong>面板没有任务</strong></summary>

- 确认 Abar 正在运行：`open ~/Applications/Abar.app`
- 在 Codex 中执行 `/hooks`，确认 Hook 已启用并信任
- 重新生成 Hook，确认 Reporter 的绝对路径仍然存在
- 使用健康接口确认本地服务正在运行

</details>

<details>
<summary><strong>端口被占用</strong></summary>

```bash
lsof -nP -iTCP:3987 -sTCP:LISTEN
```

退出占用端口的程序，或为 Abar 与 Hook 同时配置另一个端口。Abar 启动日志会记录 `server bind failed`。

</details>

<details>
<summary><strong>看不到额度</strong></summary>

- 确认 Codex 已登录
- 检查 `~/.codex/auth.json` 是否存在
- 网络、代理、令牌失效、限流或内部接口变化都可能导致刷新失败
- Abar 会在面板中显示最近一次额度刷新错误

</details>

<details>
<summary><strong>macOS 阻止打开</strong></summary>

本地构建使用 ad-hoc 签名，没有 Apple Developer ID 签名，也未经过公证。通过本仓库源码执行 `npm run setup` 后，脚本会清理本地隔离属性；不要运行来源不明的 Abar 二进制文件。

</details>

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

产物位于 `native-overlay/dist/Abar.app`。

```text
native-overlay/               Swift 核心、macOS 应用与测试
reporters/codex-hook-reporter Codex Hook Reporter
scripts/                      环境检查、安装、诊断与卸载
docs/images/                  README 与应用图像资源
.github/                      CI 和协作模板
```

## 已知限制

- 只支持 Codex，不支持 Claude、Cursor、Ollama 或多 Agent 聚合
- 只支持 Apple Silicon 和 macOS 14 以上版本
- 当前不提供自动启动、自动更新、DMG、Developer ID 签名或公证
- 无法可靠判断 Codex 当前正在使用的确切 Skill，只能展示扫描结果
- 额度依赖未公开的 ChatGPT 内部接口

## 参与贡献

提交 Issue 或 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按照 [SECURITY.md](SECURITY.md) 私下报告。

## 许可证

Abar 使用 [MIT License](LICENSE)。
