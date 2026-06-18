# Abar

Abar is a Codex-only macOS menu bar monitor. It lives in the menu bar and opens a compact popover for Codex quota, configured project path, available skills, and recent hook activity.

## What v1 Does

- Electron Tray entry with a compact React popover
- Menu-bar-only app behavior on macOS
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

`npm run dev` builds the app, packages the local macOS `.app`, and opens the real menu bar app. Use this path for status bar testing because Electron's raw dev runner can report an invisible status item on macOS.

For low-level Electron/Vite debugging only:

```bash
npm run dev:electron
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

Open the Abar menu bar popover and click **Copy install**. Paste that prompt into Codex so Codex can merge the Abar hooks into `~/.codex/hooks.json`.

After Codex edits hooks:

1. Open `/hooks` in Codex.
2. Review and trust the Abar hook definitions yourself. Abar and Codex cannot silently bypass this trust step.
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
