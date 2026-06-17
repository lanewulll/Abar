# Abar

Abar is a Codex-only macOS menu bar monitor. It shows a small status bar entry and a local dashboard for Codex quota, configured project path, available skills, and recent hook activity.

## What v1 Does

- Electron Tray entry with a compact native menu
- React dashboard for Overview, Quota, Skills, Activity, and Settings
- Local SQLite cache in Electron `userData`
- Skill scanning for project `.agents/skills`, user `~/.agents/skills`, and compatible `~/.codex/skills` locations
- Optional quota refresh from Codex local auth state and ChatGPT's internal `wham/usage` endpoint
- Local hook event receiver on `127.0.0.1:3987`
- Non-blocking Codex hook reporter

## What v1 Does Not Do

- No Claude, ChatGPT, Cursor, Ollama, or multi-agent support
- No cloud sync or accounts
- No floating desktop widget
- No automatic external quota CLI installation or token refresh
- No claim that Abar can know the exact currently active skill

## Development

```bash
npm install
npm test
npm run dev
```

If Electron download times out, retry with:

```bash
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ npm install
```

## Build

```bash
npm run build
npm run package:mac
```

The packaged app is not signed or notarized in v1.

## Codex Hooks

Open Abar Settings, copy the generated hook snippet, and merge it into `~/.codex/hooks.json` or the project `.codex/hooks.json`.

After editing hooks:

1. Restart Codex or open `/hooks`.
2. Review and trust the Abar hook definitions.
3. Keep Abar running while using Codex.

The reporter sends only to `127.0.0.1` and exits successfully if Abar is not available.

## Quota Provider

Abar v1 reads Codex auth state from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`, then requests:

```text
https://chatgpt.com/backend-api/wham/usage
```

The request uses `Authorization: Bearer <access_token>` and, when available, `ChatGPT-Account-ID`. Abar stores only sanitized quota snapshots and never logs access tokens, refresh tokens, cookies, or authorization headers.

Run a local diagnostic without starting Electron:

```bash
npm run quota:diagnose
```

The diagnostic prints whether token/account ID fields exist, the HTTP status, and a sanitized quota summary. It does not print token contents.

`wham/usage` is an undocumented internal ChatGPT endpoint, not a stable public API. If auth is missing, the token is rejected, the endpoint is rate limited, or the network/proxy path fails, Abar shows the reason and falls back to local Codex session estimates when available. The official usage view remains:

```text
https://chatgpt.com/codex/settings/usage
```
