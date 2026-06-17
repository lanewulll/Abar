import { spawn } from 'node:child_process';
import type { QuotaSnapshot, UsageWindow } from '../types';
import { redactSensitive } from '../utils/sanitize';
import { readCodexAuthState, sanitizeCodexAuthState, type CodexAuthState, type ReadCodexAuthStateOptions } from './codexAuth';
import { readLocalCodexRateLimitEstimate } from './localRateLimitEstimate';

export const WHAM_USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage';

export async function refreshQuotaSnapshot(): Promise<QuotaSnapshot> {
  const whamSnapshot = await refreshWhamUsageSnapshot();
  if (!whamSnapshot.error || whamSnapshot.windows.length > 0) {
    return whamSnapshot;
  }

  const localEstimate = await readLocalCodexRateLimitEstimate();
  if (localEstimate) {
    return {
      ...localEstimate,
      error: `Internal web API unavailable: ${whamSnapshot.error} Showing local estimate from Codex session files.`,
      raw: {
        ...(typeof localEstimate.raw === 'object' && localEstimate.raw ? localEstimate.raw : {}),
        upstreamSource: whamSnapshot.source,
        upstreamError: whamSnapshot.error
      }
    };
  }

  return whamSnapshot;
}

export async function refreshWhamUsageSnapshot(
  options: ReadCodexAuthStateOptions & { timeoutMs?: number } = {}
): Promise<QuotaSnapshot> {
  const auth = await readCodexAuthState(options);
  if (!auth.accessToken) {
    return authStateSnapshot(auth, auth.error ?? 'Codex auth.json does not contain an access token.');
  }

  try {
    const result = await requestWhamUsage(auth, options.timeoutMs ?? 15_000);
    if (result.status < 200 || result.status >= 300) {
      return whamErrorSnapshot(auth, httpStatusError(result.status, result.body));
    }

    const raw = JSON.parse(result.body) as unknown;
    const snapshot = normalizeWhamUsageJson(raw);
    return {
      ...snapshot,
      raw: {
        endpoint: WHAM_USAGE_URL,
        authSource: 'codex_auth_state',
        auth: sanitizeCodexAuthState(auth),
        response: redactSensitive(raw)
      }
    };
  } catch (error) {
    return whamErrorSnapshot(auth, formatWhamRequestError(error));
  }
}

export function normalizeWhamUsageJson(raw: unknown): QuotaSnapshot {
  const data = isRecord(raw) ? raw : {};
  const rateLimit = getRecord(data.rate_limit);
  const windows: UsageWindow[] = [];

  for (const rawWindow of [rateLimit?.primary_window, rateLimit?.secondary_window]) {
    const window = normalizeWhamWindow(rawWindow);
    if (window) {
      windows.push(window);
    }
  }

  windows.push(...normalizeAdditionalRateLimits(data.additional_rate_limits));

  const credits = normalizeCredits(data.credits);
  const snapshot: QuotaSnapshot = {
    provider: 'codex',
    source: 'internal_web_api',
    confidence: windows.length > 0 ? 'high' : 'low',
    windows,
    ...(credits ? { credits } : {}),
    updatedAt: new Date().toISOString(),
    raw: redactSensitive(raw)
  };

  if (windows.length === 0) {
    snapshot.error = 'No usable Codex quota windows found in internal web API response.';
  }

  return snapshot;
}

export function normalizePiCodexStatusJson(raw: unknown): QuotaSnapshot {
  const data = isRecord(raw) ? raw : {};
  const defaultLimit = getRecord(data.defaultLimit) ?? {};
  const windows: UsageWindow[] = [];

  const primary = getRecord(defaultLimit.primary) ?? getRecord(data.primary) ?? getRecord(data.five_hour);
  const secondary = getRecord(defaultLimit.secondary) ?? getRecord(data.secondary) ?? getRecord(data.weekly);

  const primaryWindow = normalizeWindow('5h', primary);
  const secondaryWindow = normalizeWindow('weekly', secondary);

  if (primaryWindow) {
    windows.push(primaryWindow);
  }
  if (secondaryWindow) {
    windows.push(secondaryWindow);
  }

  const credits = normalizeCredits(data.credits ?? data.creditBalance ?? data.balance);
  const updatedAt = normalizeUpdatedAt(data.updatedAt ?? data.updated_at ?? data.fetchedAt);
  const snapshot: QuotaSnapshot = {
    provider: 'codex',
    source: 'external_cli',
    confidence: windows.length > 0 ? 'high' : 'low',
    windows,
    ...(credits ? { credits } : {}),
    updatedAt,
    raw: redactSensitive(raw)
  };

  if (windows.length === 0) {
    snapshot.error = 'No usable Codex quota windows found in external CLI output.';
  }

  return snapshot;
}

function normalizeAdditionalRateLimits(raw: unknown): UsageWindow[] {
  if (!Array.isArray(raw)) {
    return [];
  }

  const windows: UsageWindow[] = [];
  const usedIds = new Set<string>();
  for (const entry of raw) {
    const record = getRecord(entry);
    if (!record) {
      continue;
    }

    const rateLimit = getRecord(record.rate_limit);
    const baseLabel = firstNonEmpty(record.limit_name, record.metered_feature) ?? 'Codex extra limit';
    for (const rawWindow of [rateLimit?.primary_window, rateLimit?.secondary_window]) {
      const window = normalizeWhamWindow(rawWindow, baseLabel, record);
      if (!window) {
        continue;
      }

      const id = window.sourceId ?? `${window.label ?? baseLabel}:${window.name}`;
      if (usedIds.has(id)) {
        continue;
      }
      usedIds.add(id);
      windows.push(window);
    }
  }

  return windows;
}

function normalizeWhamWindow(raw: unknown, baseLabel?: string, owner?: Record<string, unknown>): UsageWindow | undefined {
  const value = getRecord(raw);
  if (!value) {
    return undefined;
  }

  const usedPercent = numberFrom(value.used_percent ?? value.usedPercent ?? value.utilization);
  const remainingPercent =
    numberFrom(value.remaining_percent ?? value.remainingPercent) ??
    (usedPercent === undefined ? undefined : clampPercent(100 - usedPercent));
  const windowSeconds = numberFrom(value.limit_window_seconds ?? value.limitWindowSeconds);
  const resetsAt = normalizeResetAt(value.reset_at ?? value.resetAt);
  const resetInSeconds =
    numberFrom(value.reset_after_seconds ?? value.resetAfterSeconds ?? value.reset_in_seconds ?? value.resetInSeconds) ??
    secondsUntil(resetsAt);

  if (usedPercent === undefined && remainingPercent === undefined && !resetsAt && resetInSeconds === undefined) {
    return undefined;
  }

  const detectedName = windowNameFromSeconds(windowSeconds);
  const name = baseLabel ? 'unknown' : detectedName;
  const extraLabel = baseLabel ? extraWindowLabel(baseLabel, detectedName, windowSeconds) : undefined;
  const sourceId = baseLabel ? extraWindowId(baseLabel, detectedName, windowSeconds, owner) : undefined;

  return {
    name,
    ...(extraLabel ? { label: extraLabel } : {}),
    ...(sourceId ? { sourceId } : {}),
    ...(usedPercent !== undefined ? { usedPercent: clampPercent(usedPercent) } : {}),
    ...(remainingPercent !== undefined ? { remainingPercent: clampPercent(remainingPercent) } : {}),
    unit: 'unknown',
    ...(resetsAt ? { resetsAt } : {}),
    ...(resetInSeconds !== undefined ? { resetInSeconds: Math.max(0, Math.round(resetInSeconds)) } : {})
  };
}

function windowNameFromSeconds(seconds: number | undefined): UsageWindow['name'] {
  if (seconds === 18_000) {
    return '5h';
  }
  if (seconds === 604_800) {
    return 'weekly';
  }
  return 'unknown';
}

function extraWindowLabel(baseLabel: string, name: UsageWindow['name'], windowSeconds: number | undefined): string {
  if (name === '5h') {
    return `${baseLabel} 5h`;
  }
  if (name === 'weekly') {
    return `${baseLabel} Weekly`;
  }
  if (windowSeconds) {
    return `${baseLabel} ${Math.round(windowSeconds / 60)}m`;
  }
  return baseLabel;
}

function extraWindowId(
  baseLabel: string,
  name: UsageWindow['name'],
  windowSeconds: number | undefined,
  owner?: Record<string, unknown>
): string {
  const source = firstNonEmpty(owner?.metered_feature, owner?.limit_name, baseLabel) ?? baseLabel;
  return `codex-${slug(source)}-${name === 'unknown' ? windowSeconds ?? 'unknown' : name}`;
}

function normalizeWindow(name: UsageWindow['name'], value: Record<string, unknown> | undefined): UsageWindow | null {
  if (!value) {
    return null;
  }

  const remainingPercent = numberFrom(
    value.leftPercent ?? value.remainingPercent ?? value.remaining_percent ?? value.left_percent
  );
  const explicitUsedPercent = numberFrom(value.usedPercent ?? value.used_percent);
  const usedPercent =
    explicitUsedPercent ?? (remainingPercent === undefined ? undefined : clampPercent(100 - remainingPercent));
  const used = numberFrom(value.used ?? value.usedAmount ?? value.used_amount);
  const limit = numberFrom(value.limit ?? value.total ?? value.limitAmount ?? value.limit_amount);
  const resetsAt = normalizeResetAt(value.resetAt ?? value.reset_at ?? value.resetsAt ?? value.resets_at);
  const resetInSeconds =
    numberFrom(value.resetInSeconds ?? value.reset_in_seconds) ?? secondsUntil(resetsAt);

  if (
    remainingPercent === undefined &&
    usedPercent === undefined &&
    used === undefined &&
    limit === undefined &&
    !resetsAt
  ) {
    return null;
  }

  return {
    name,
    ...(usedPercent !== undefined ? { usedPercent: clampPercent(usedPercent) } : {}),
    ...(remainingPercent !== undefined ? { remainingPercent: clampPercent(remainingPercent) } : {}),
    ...(used !== undefined ? { used } : {}),
    ...(limit !== undefined ? { limit } : {}),
    unit: normalizeUnit(value.unit),
    ...(resetsAt ? { resetsAt } : {}),
    ...(resetInSeconds !== undefined ? { resetInSeconds } : {})
  };
}

function normalizeCredits(value: unknown): QuotaSnapshot['credits'] | undefined {
  if (typeof value === 'number') {
    return { remaining: value, unit: 'credits' };
  }

  const record = getRecord(value);
  if (!record) {
    return undefined;
  }

  if (record.has_credits === false && record.balance === undefined && record.remaining === undefined) {
    return undefined;
  }

  const remaining = numberFrom(record.remaining ?? record.left ?? record.balance ?? record.amount);
  const total = numberFrom(record.total ?? record.limit);
  if (remaining === undefined && total === undefined) {
    return undefined;
  }

  return {
    ...(remaining !== undefined ? { remaining } : {}),
    ...(total !== undefined ? { total } : {}),
    unit: String(record.unit ?? 'credits')
  };
}

type WhamRequestResult = {
  status: number;
  body: string;
};

function requestWhamUsage(auth: CodexAuthState, timeoutMs: number): Promise<WhamRequestResult> {
  return new Promise((resolve, reject) => {
    const seconds = Math.max(1, Math.ceil(timeoutMs / 1000));
    const args = ['--silent', '--show-error', '--location', '--max-time', String(seconds), '--write-out', '\n__ABAR_HTTP_STATUS__:%{http_code}', '--config', '-'];
    const child = spawn('curl', args, {
      stdio: ['pipe', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      reject(new Error(`Timed out after ${timeoutMs}ms while requesting wham/usage.`));
    }, timeoutMs + 500);

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code !== 0) {
        reject(new Error(curlFailureMessage(code, stderr)));
        return;
      }

      const marker = '\n__ABAR_HTTP_STATUS__:';
      const markerIndex = stdout.lastIndexOf(marker);
      if (markerIndex === -1) {
        reject(new Error('wham/usage response did not include an HTTP status marker.'));
        return;
      }

      const body = stdout.slice(0, markerIndex);
      const status = Number(stdout.slice(markerIndex + marker.length).trim());
      if (!Number.isFinite(status)) {
        reject(new Error('wham/usage response included an invalid HTTP status marker.'));
        return;
      }
      resolve({ status, body });
    });

    child.stdin.end(curlConfig(auth));
  });
}

function curlConfig(auth: CodexAuthState): string {
  const headers = [
    `Authorization: Bearer ${auth.accessToken}`,
    'Accept: application/json',
    'User-Agent: Abar/0.1 CodexQuotaProvider'
  ];
  if (auth.accountId) {
    headers.push(`ChatGPT-Account-ID: ${auth.accountId}`);
  }

  return [
    `url = "${WHAM_USAGE_URL}"`,
    'request = "GET"',
    ...headers.map((header) => `header = "${escapeCurlConfigValue(header)}"`)
  ].join('\n');
}

function escapeCurlConfigValue(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function curlFailureMessage(code: number | null, stderr: string): string {
  const safeStderr = sanitizeErrorText(stderr).trim();
  if (code === 28 || /timed out|timeout/i.test(safeStderr)) {
    return 'Timed out while requesting wham/usage.';
  }
  if (/proxy/i.test(safeStderr)) {
    return `Proxy/network error while requesting wham/usage: ${safeStderr}`;
  }
  if (code === 6 || code === 7 || code === 35 || code === 56) {
    return `Network error while requesting wham/usage: ${safeStderr || `curl exited with ${code}`}`;
  }
  return `Unable to request wham/usage: ${safeStderr || `curl exited with ${code}`}`;
}

function httpStatusError(status: number, body: string): string {
  if (status === 401 || status === 403) {
    return `Codex auth token was rejected by wham/usage (HTTP ${status}). The token may be expired; run \`codex\` to re-authenticate. Abar has not implemented refresh_token renewal yet.`;
  }
  if (status === 429) {
    return 'wham/usage returned HTTP 429. The internal usage endpoint is rate limited; try again later.';
  }
  if (status >= 500) {
    return `wham/usage returned HTTP ${status}. ChatGPT usage service may be temporarily unavailable.`;
  }
  return `wham/usage returned HTTP ${status}: ${sanitizeErrorText(body).slice(0, 300) || 'No response body.'}`;
}

function formatWhamRequestError(error: unknown): string {
  if (error instanceof SyntaxError) {
    return `wham/usage returned invalid JSON: ${error.message}`;
  }
  if (error instanceof Error) {
    return sanitizeErrorText(error.message);
  }
  return sanitizeErrorText(String(error));
}

function authStateSnapshot(auth: CodexAuthState, error: string): QuotaSnapshot {
  return {
    provider: 'codex',
    source: 'codex_auth_state',
    confidence: 'low',
    windows: [],
    updatedAt: new Date().toISOString(),
    raw: {
      authSource: 'codex_auth_state',
      auth: sanitizeCodexAuthState(auth)
    },
    error
  };
}

function whamErrorSnapshot(auth: CodexAuthState, error: string): QuotaSnapshot {
  return {
    provider: 'codex',
    source: 'internal_web_api',
    confidence: 'low',
    windows: [],
    updatedAt: new Date().toISOString(),
    raw: {
      endpoint: WHAM_USAGE_URL,
      authSource: 'codex_auth_state',
      auth: sanitizeCodexAuthState(auth)
    },
    error
  };
}

function normalizeResetAt(value: unknown): string | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) {
    const millis = value > 1_000_000_000_000 ? value : value * 1000;
    return new Date(millis).toISOString();
  }

  if (typeof value === 'string' && value.trim()) {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) {
      return normalizeResetAt(numeric);
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
  }

  return undefined;
}

function normalizeUpdatedAt(value: unknown): string {
  return normalizeResetAt(value) ?? new Date().toISOString();
}

function secondsUntil(isoDate: string | undefined): number | undefined {
  if (!isoDate) {
    return undefined;
  }
  const delta = Math.round((new Date(isoDate).getTime() - Date.now()) / 1000);
  return Number.isFinite(delta) ? Math.max(0, delta) : undefined;
}

function normalizeUnit(value: unknown): UsageWindow['unit'] {
  if (value === 'messages' || value === 'tokens' || value === 'credits') {
    return value;
  }
  return 'unknown';
}

function numberFrom(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return undefined;
}

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value * 10) / 10));
}

function getRecord(value: unknown): Record<string, unknown> | undefined {
  return isRecord(value) ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function firstNonEmpty(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) {
      return value.trim();
    }
  }
  return undefined;
}

function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function sanitizeErrorText(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
    .replace(/(access[_-]?token|refresh[_-]?token|authorization|cookie|secret|credential)["'\s:=]+[^"'\s,}]+/gi, '$1=[REDACTED]')
    .trim();
}

export function formatQuotaCliError(error: unknown): string {
  const stderr = error && typeof error === 'object' && 'stderr' in error ? String(error.stderr ?? '') : '';
  const message = error instanceof Error ? error.message : String(error);
  const combined = `${message}\n${stderr}`;

  if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
    return 'Legacy quota CLI not found. Abar now defaults to wham/usage via Codex auth state; run `npm run quota:diagnose` for the supported local diagnostic.';
  }
  if (/pi-codex-status:\s*fetch failed|fetch failed/i.test(combined)) {
    return [
      'Legacy quota CLI could not fetch Codex usage.',
      'Abar now uses https://chatgpt.com/backend-api/wham/usage through local Codex auth state instead of relying on pi-codex-status.',
      'Run `npm run quota:diagnose` for a sanitized provider check, or open https://chatgpt.com/codex/settings/usage for the official usage view.'
    ].join(' ');
  }
  if (error instanceof SyntaxError) {
    return `Quota CLI returned invalid JSON: ${error.message}`;
  }
  if (error instanceof Error) {
    return `Quota CLI failed: ${error.message}`;
  }
  return `Quota CLI failed: ${String(error)}`;
}
