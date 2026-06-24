# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的基本格式，并使用语义化版本号。

## [未发布]

### 新增

- 中文 README、贡献指南、安全政策与 GitHub 协作模板
- Apple Silicon 环境检查、本地安装与卸载脚本
- macOS 应用图标与 `Abar.app` 统一产物
- GitHub Actions 测试和 release 构建验证

### 修复

- 根据最新 Codex Hook 动态更新项目 Skill 扫描路径
- 统一应用与 Reporter 的本地端口配置
- 移除未被服务端验证的 Reporter secret 配置

## [0.1.0] - 2026-06-24

### 新增

- 原生 macOS 顶部悬浮面板
- Codex 额度、任务活动和 Skill 扫描
- Codex Hook Reporter 与本地 SQLite 存储
