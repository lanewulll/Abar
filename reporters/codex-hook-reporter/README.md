# Abar Codex Hook Reporter

`reporter.js` reads a Codex hook payload from stdin and posts it to Abar at `http://127.0.0.1:3987/events`.

It always exits `0`, even when Abar is not running, so Codex activity is not blocked by monitoring.

Environment variables:

- `ABAR_SERVER_PORT`: local Abar port, default `3987`
- `ABAR_EVENT_SECRET`: optional shared secret sent as `x-abar-secret`
- `ABAR_REPORTER_TIMEOUT_MS`: request timeout, default `800`
- `ABAR_REPORTER_DEBUG=1`: write lightweight connection errors to `~/Library/Logs/Abar/codex-hook-reporter.log`

Generate a manual hook snippet:

```bash
node reporters/codex-hook-reporter/install.js
```
