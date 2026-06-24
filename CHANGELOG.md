# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的基本格式，并使用语义化版本号。

## [未发布]

### 新增

- 中文 README、贡献指南、安全政策与 GitHub 协作模板
- Apple Silicon 环境检查、本地安装与卸载脚本
- macOS 应用图标与 `Abar.app` 统一产物
- GitHub Actions 测试和 release 构建验证
- 普通用户状态中心、失败修复路径、隐私与本地数据页面
- Hook 安全预览/备份/合并、脱敏诊断报告与完整卸载
- GitHub 每日轻量更新检查与状态中心更新入口

### 修复

- 根据最新 Codex Hook 动态更新项目 Skill 扫描路径
- 统一应用与 Reporter 的本地端口配置
- 移除未被服务端验证的 Reporter secret 配置
- Reporter 改为随 App 安装的稳定路径，移动源码仓库不再破坏新 Hook
- 事件存储最小化并使用滚动 24 小时保留；迁移清理旧 prompt、transcript 与额度原始响应
- 额度刷新失败时继续展示最近一次成功快照

## [0.1.0] - 2026-06-24

### 新增

- 原生 macOS 顶部悬浮面板
- Codex 额度、任务活动和 Skill 扫描
- Codex Hook Reporter 与本地 SQLite 存储
