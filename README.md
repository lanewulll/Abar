# Abar

Abar is a Codex-only native macOS overlay monitor. It lives at the top of the screen, expands on hover, and shows Codex quota, available skills, and recent hook activity.

## What v1 Does

- Native Swift/AppKit overlay with a hover-to-expand `NSPanel`
- Local SQLite cache in `~/Library/Application Support/abar/abar.sqlite`
- Skill scanning for project `.agents/skills`, user `~/.agents/skills`, and compatible `~/.codex/skills` locations
- Quota refresh every 30 seconds from Codex local auth state and ChatGPT's internal `wham/usage` endpoint
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
npm test
npm run dev
```

`npm run dev` builds and opens the native macOS app from `native-overlay/`.

## Build

```bash
npm run build
npm run package:mac
```

The local app is signed ad-hoc for development and is not notarized in v1.

## Codex Hooks

Generate the hook snippet:

```bash
node reporters/codex-hook-reporter/install.js
```

Merge the printed hooks into `~/.codex/hooks.json`.

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

`wham/usage` is an undocumented internal ChatGPT endpoint, not a stable public API. If auth is missing, the token is rejected, the endpoint is rate limited, or the network/proxy path fails, Abar shows the reason from the failed refresh. The official usage view remains:

```text
https://chatgpt.com/codex/settings/usage
```
