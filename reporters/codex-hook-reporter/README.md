# Abar Codex Hook Reporter

`reporter.js` 从标准输入读取 Codex Hook JSON，并将事件发送到 Abar：

```text
http://127.0.0.1:3987/events
```

Reporter 在 Abar 未运行、请求超时或输入无效时也会以状态码 `0` 退出，避免监控功能阻塞 Codex。

## 生成 Hook 配置

在仓库根目录执行：

```bash
node reporters/codex-hook-reporter/install.js
```

将输出的 `hooks` 合并到 `~/.codex/hooks.json`，随后在 Codex 中运行 `/hooks` 并手动信任。

## 环境变量

- `ABAR_SERVER_PORT`：本地 Abar 端口，默认 `3987`
- `ABAR_REPORTER_TIMEOUT_MS`：请求超时，默认 `800` 毫秒
- `ABAR_REPORTER_DEBUG=1`：将轻量连接错误写入 `~/Library/Logs/Abar/codex-hook-reporter.log`

Reporter 不支持远程地址，只会连接 `127.0.0.1`。

## 测试

```bash
npm run test:hooks
```
