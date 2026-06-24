# Abar Codex Hook Reporter

`reporter.js` 从标准输入读取 Codex Hook JSON，并将事件发送到 Abar：

```text
http://127.0.0.1:3987/events
```

Reporter 在 Abar 未运行、请求超时或输入无效时也会以状态码 `0` 退出，避免监控功能阻塞 Codex。

## 生成 Hook 配置

在仓库根目录执行：

推荐使用仓库根目录的安全维护命令：

```bash
npm run hooks:preview
npm run hooks:install
```

安装命令会备份、结构化合并并校验 `~/.codex/hooks.json`，不会覆盖用户已有 Hook。Reporter 随应用安装到稳定路径，不再依赖源码仓库位置。随后仍需在 Codex 中运行 `/hooks` 并由用户手动信任。

`node reporters/codex-hook-reporter/install.js` 仍保留为只输出 JSON 的开发与人工配置回退方式。

## 环境变量

- `ABAR_SERVER_PORT`：本地 Abar 端口，默认 `3987`
- `ABAR_REPORTER_TIMEOUT_MS`：请求超时，默认 `800` 毫秒
- `ABAR_REPORTER_DEBUG=1`：将轻量连接错误写入 `~/Library/Logs/Abar/codex-hook-reporter.log`

Reporter 不支持远程地址，只会连接 `127.0.0.1`。

## 测试

```bash
npm run test:hooks
```
