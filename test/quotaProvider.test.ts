import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { readCodexAuthState, sanitizeCodexAuthState } from '../backend/codex/codexAuth';
import { readLocalCodexRateLimitEstimate } from '../backend/codex/localRateLimitEstimate';
import {
  formatQuotaCliError,
  normalizePiCodexStatusJson,
  normalizeWhamUsageJson
} from '../backend/codex/quotaProvider';

describe('normalizePiCodexStatusJson', () => {
  it('normalizes primary, weekly, credits, and reset fields', () => {
    const snapshot = normalizePiCodexStatusJson({
      updatedAt: '2026-06-16T12:00:00.000Z',
      defaultLimit: {
        primary: {
          leftPercent: 38,
          resetAt: 1780000000,
          limitWindowSeconds: 18000
        },
        secondary: {
          leftPercent: 62,
          resetAt: '2026-06-20T00:00:00.000Z'
        }
      },
      credits: {
        remaining: 139.9,
        total: 200
      }
    });

    expect(snapshot.provider).toBe('codex');
    expect(snapshot.source).toBe('external_cli');
    expect(snapshot.confidence).toBe('high');
    expect(snapshot.windows).toMatchObject([
      { name: '5h', usedPercent: 62, remainingPercent: 38, unit: 'unknown' },
      { name: 'weekly', usedPercent: 38, remainingPercent: 62, unit: 'unknown' }
    ]);
    expect(snapshot.credits?.remaining).toBe(139.9);
    expect(snapshot.raw).not.toHaveProperty('access_token');
  });

  it('returns a low-confidence error snapshot for invalid quota shapes', () => {
    const snapshot = normalizePiCodexStatusJson({ message: 'not quota' });

    expect(snapshot.confidence).toBe('low');
    expect(snapshot.error).toContain('No usable Codex quota windows');
    expect(snapshot.windows).toEqual([]);
  });

  it('explains legacy CLI fetch failures without making it the default provider', () => {
    const error = Object.assign(new Error('Command failed: pi-codex-status json\npi-codex-status: fetch failed'), {
      stderr: 'pi-codex-status: fetch failed\n'
    });

    expect(formatQuotaCliError(error)).toContain('Legacy quota CLI could not fetch Codex usage');
    expect(formatQuotaCliError(error)).toContain('https://chatgpt.com/backend-api/wham/usage');
    expect(formatQuotaCliError(error)).toContain('npm run quota:diagnose');
    expect(formatQuotaCliError(error)).toContain('https://chatgpt.com/codex/settings/usage');
  });
});

describe('readCodexAuthState', () => {
  it('loads Codex auth.json from CODEX_HOME-style roots without exposing tokens in diagnostics', async () => {
    const root = await mkdtemp(join(tmpdir(), 'abar-codex-auth-'));
    await writeFile(
      join(root, 'auth.json'),
      JSON.stringify({
        tokens: {
          access_token: 'access.secret.token',
          refresh_token: 'refresh.secret.token',
          account_id: 'acct_123456789'
        },
        last_refresh: '2026-06-10T12:00:00.000Z'
      })
    );

    const auth = await readCodexAuthState({ codexHome: root });
    const diagnostic = sanitizeCodexAuthState(auth);

    expect(auth.accessToken).toBe('access.secret.token');
    expect(auth.accountId).toBe('acct_123456789');
    expect(auth.accountIdSource).toBe('auth.json');
    expect(diagnostic).toMatchObject({
      hasAccessToken: true,
      hasRefreshToken: true,
      hasAccountId: true,
      accountIdSource: 'auth.json',
      lastRefresh: '2026-06-10T12:00:00.000Z'
    });
    expect(JSON.stringify(diagnostic)).not.toContain('secret');
    expect(JSON.stringify(diagnostic)).not.toContain('acct_123456789');
  });
});

describe('normalizeWhamUsageJson', () => {
  it('maps wham windows by limit_window_seconds instead of primary/secondary order', () => {
    const snapshot = normalizeWhamUsageJson({
      plan_type: 'pro',
      rate_limit: {
        primary_window: {
          used_percent: 38,
          limit_window_seconds: 604800,
          reset_at: 1780000000
        },
        secondary_window: {
          used_percent: 62,
          limit_window_seconds: 18000,
          reset_after_seconds: 3600
        }
      },
      credits: {
        has_credits: true,
        balance: '139.9'
      },
      additional_rate_limits: [
        {
          limit_name: 'Codex Spark',
          metered_feature: 'codex_bengalfox',
          rate_limit: {
            primary_window: {
              used_percent: 71,
              limit_window_seconds: 18000,
              reset_at: 1780000300
            },
            secondary_window: {
              used_percent: 22,
              limit_window_seconds: 604800,
              reset_at: 1780000400
            }
          }
        },
        {
          limit_name: 'Malformed extra',
          rate_limit: {
            primary_window: {
              used_percent: 'not a number',
              limit_window_seconds: 18000
            }
          }
        }
      ]
    });

    expect(snapshot.source).toBe('internal_web_api');
    expect(snapshot.confidence).toBe('high');
    expect(snapshot.windows.find((window) => window.name === '5h')).toMatchObject({
      name: '5h',
      usedPercent: 62,
      remainingPercent: 38,
      resetInSeconds: 3600
    });
    expect(snapshot.windows.find((window) => window.name === 'weekly')).toMatchObject({
      name: 'weekly',
      usedPercent: 38,
      remainingPercent: 62,
      resetsAt: '2026-05-28T20:26:40.000Z'
    });
    expect(snapshot.windows.filter((window) => window.name === 'unknown')).toMatchObject([
      {
        label: 'Codex Spark 5h',
        usedPercent: 71,
        remainingPercent: 29
      },
      {
        label: 'Codex Spark Weekly',
        usedPercent: 22,
        remainingPercent: 78
      }
    ]);
    expect(snapshot.credits?.remaining).toBe(139.9);
    expect(snapshot.raw).not.toHaveProperty('access_token');
  });

  it('returns a low-confidence error when wham usage has no usable windows', () => {
    const snapshot = normalizeWhamUsageJson({ rate_limit: { primary_window: null } });

    expect(snapshot.confidence).toBe('low');
    expect(snapshot.error).toContain('No usable Codex quota windows');
  });
});

describe('readLocalCodexRateLimitEstimate', () => {
  it('extracts the newest token_count rate limits from Codex session files', async () => {
    const root = await mkdtemp(join(tmpdir(), 'abar-codex-sessions-'));
    const sessionDir = join(root, 'sessions', '2026', '06', '17');
    await mkdir(sessionDir, { recursive: true });
    await writeFile(
      join(sessionDir, 'rollout-test.jsonl'),
      [
        JSON.stringify({
          timestamp: '2026-06-17T00:00:00.000Z',
          type: 'event_msg',
          payload: {
            type: 'token_count',
            rate_limits: {
              secondary: {
                used_percent: 33,
                window_minutes: 10080,
                resets_at: 1780000000
              }
            }
          }
        }),
        JSON.stringify({
          timestamp: '2026-06-17T00:01:00.000Z',
          type: 'event_msg',
          payload: {
            type: 'token_count',
            rate_limits: {
              primary: {
                used_percent: 44,
                window_minutes: 300,
                resets_in_seconds: 120
              }
            }
          }
        })
      ].join('\n')
    );

    const snapshot = await readLocalCodexRateLimitEstimate({ codexHome: root });

    expect(snapshot?.source).toBe('local_estimate');
    expect(snapshot?.confidence).toBe('low');
    expect(snapshot?.windows).toMatchObject([
      {
        name: '5h',
        usedPercent: 44,
        remainingPercent: 56,
        resetInSeconds: 120
      }
    ]);
  });
});
