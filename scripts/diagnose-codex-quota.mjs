#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const WHAM_USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage';
const OPENAI_AUTH_CLAIM = 'https://api.openai.com/auth';
const TIMEOUT_MS = Number(process.env.ABAR_QUOTA_TIMEOUT_MS || 15000);

main().catch((error) => {
  console.error(JSON.stringify({ ok: false, error: sanitizeError(String(error?.message ?? error)) }, null, 2));
  process.exitCode = 1;
});

async function main() {
  const auth = await readCodexAuth();
  const result = {
    ok: false,
    source: 'internal_web_api / codex_auth_state',
    endpoint: WHAM_USAGE_URL,
    auth: auth.diagnostic
  };

  if (!auth.accessToken) {
    result.error = auth.error || 'Codex auth.json does not contain tokens.access_token.';
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = 1;
    return;
  }

  try {
    const response = await requestWhamUsage(auth, TIMEOUT_MS);
    result.httpStatus = response.status;

    if (response.status < 200 || response.status >= 300) {
      result.error = httpStatusError(response.status, response.body);
      console.log(JSON.stringify(result, null, 2));
      process.exitCode = 1;
      return;
    }

    const json = JSON.parse(response.body);
    result.ok = true;
    result.quota = summarizeWhamUsage(json);
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    result.error = sanitizeError(String(error?.message ?? error));
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = 1;
  }
}

async function readCodexAuth() {
  const codexHome = process.env.CODEX_HOME?.trim() || join(homedir(), '.codex');
  const authPath = join(codexHome, 'auth.json');
  const diagnostic = {
    authPath,
    hasAccessToken: false,
    hasRefreshToken: false,
    hasIdToken: false,
    hasAccountId: false,
    accountIdSource: 'none'
  };

  try {
    const json = JSON.parse(await readFile(authPath, 'utf8'));
    const tokens = isRecord(json?.tokens) ? json.tokens : {};
    const accessToken = stringValue(tokens.access_token) ?? stringValue(tokens.accessToken);
    const refreshToken = stringValue(tokens.refresh_token) ?? stringValue(tokens.refreshToken);
    const idToken = stringValue(tokens.id_token) ?? stringValue(tokens.idToken);
    const explicitAccountId = stringValue(tokens.account_id) ?? stringValue(tokens.accountId);
    const accessPayload = parseJwtPayload(accessToken);
    const idPayload = parseJwtPayload(idToken);
    const jwtAccountId = accountIdFromJwtPayload(accessPayload) ?? accountIdFromJwtPayload(idPayload);
    const accountId = explicitAccountId ?? jwtAccountId;
    const expiresAt = typeof accessPayload?.exp === 'number' ? new Date(accessPayload.exp * 1000).toISOString() : undefined;

    Object.assign(diagnostic, {
      hasAccessToken: Boolean(accessToken),
      hasRefreshToken: Boolean(refreshToken),
      hasIdToken: Boolean(idToken),
      hasAccountId: Boolean(accountId),
      accountIdSource: explicitAccountId ? 'auth.json' : jwtAccountId ? 'jwt' : 'none',
      ...(accountId ? { maskedAccountId: maskIdentifier(accountId) } : {}),
      ...(expiresAt ? { accessTokenExpiresAt: expiresAt } : {}),
      ...(typeof json?.last_refresh === 'string' ? { lastRefresh: json.last_refresh } : {})
    });

    return {
      accessToken,
      accountId,
      diagnostic
    };
  } catch (error) {
    return {
      diagnostic,
      error:
        error && typeof error === 'object' && error.code === 'ENOENT'
          ? 'Codex auth.json not found. Run `codex` and sign in, or set CODEX_HOME.'
          : `Unable to read Codex auth.json: ${sanitizeError(String(error?.message ?? error))}`
    };
  }
}

function requestWhamUsage(auth, timeoutMs) {
  return new Promise((resolve, reject) => {
    const args = [
      '--silent',
      '--show-error',
      '--location',
      '--max-time',
      String(Math.max(1, Math.ceil(timeoutMs / 1000))),
      '--write-out',
      '\n__ABAR_HTTP_STATUS__:%{http_code}',
      '--config',
      '-'
    ];
    const child = spawn('curl', args, { stdio: ['pipe', 'pipe', 'pipe'] });
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
      resolve({ status, body });
    });

    child.stdin.end(curlConfig(auth));
  });
}

function curlConfig(auth) {
  const headers = [
    `Authorization: Bearer ${auth.accessToken}`,
    'Accept: application/json',
    'User-Agent: Abar/0.1 CodexQuotaDiagnostic'
  ];
  if (auth.accountId) {
    headers.push(`ChatGPT-Account-ID: ${auth.accountId}`);
  }
  return [
    `url = "${WHAM_USAGE_URL}"`,
    'request = "GET"',
    ...headers.map((header) => `header = "${header.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`)
  ].join('\n');
}

function summarizeWhamUsage(json) {
  const rateLimit = isRecord(json?.rate_limit) ? json.rate_limit : {};
  const windows = [rateLimit.primary_window, rateLimit.secondary_window]
    .map((window) => summarizeWindow(window))
    .filter(Boolean);
  const additional = Array.isArray(json?.additional_rate_limits)
    ? json.additional_rate_limits.flatMap((entry) => {
        const rate = isRecord(entry?.rate_limit) ? entry.rate_limit : {};
        const label = stringValue(entry?.limit_name) ?? stringValue(entry?.metered_feature) ?? 'Codex extra limit';
        return [rate.primary_window, rate.secondary_window]
          .map((window) => summarizeWindow(window, label))
          .filter(Boolean);
      })
    : [];

  const credits = summarizeCredits(json?.credits);
  return {
    planType: stringValue(json?.plan_type) ?? 'unknown',
    windows,
    additionalRateLimits: additional,
    ...(credits ? { credits } : {})
  };
}

function summarizeWindow(raw, label) {
  if (!isRecord(raw)) return undefined;
  const usedPercent = numberFrom(raw.used_percent ?? raw.usedPercent ?? raw.utilization);
  const seconds = numberFrom(raw.limit_window_seconds ?? raw.limitWindowSeconds);
  const name = windowNameFromSeconds(seconds);
  if (usedPercent === undefined && !raw.reset_at && !raw.reset_after_seconds) {
    return undefined;
  }
  return {
    name: label ? 'extra' : name,
    ...(label ? { label: `${label}${name === '5h' ? ' 5h' : name === 'weekly' ? ' Weekly' : ''}` } : {}),
    ...(usedPercent !== undefined ? { usedPercent, remainingPercent: Math.max(0, Math.min(100, 100 - usedPercent)) } : {}),
    ...(seconds ? { limitWindowSeconds: seconds } : {}),
    ...(raw.reset_at ? { resetsAt: new Date(Number(raw.reset_at) * 1000).toISOString() } : {}),
    ...(raw.reset_after_seconds ? { resetInSeconds: Number(raw.reset_after_seconds) } : {})
  };
}

function summarizeCredits(raw) {
  if (!isRecord(raw)) return undefined;
  const balance = numberFrom(raw.balance ?? raw.remaining ?? raw.amount);
  if (balance === undefined) return undefined;
  return { remaining: balance, unit: 'credits' };
}

function windowNameFromSeconds(seconds) {
  if (seconds === 18000) return '5h';
  if (seconds === 604800) return 'weekly';
  return 'unknown';
}

function httpStatusError(status, body) {
  if (status === 401 || status === 403) {
    return `Codex auth token was rejected by wham/usage (HTTP ${status}). The token may be expired; run \`codex\` to re-authenticate.`;
  }
  if (status === 429) return 'wham/usage returned HTTP 429. Try again later.';
  if (status >= 500) return `wham/usage returned HTTP ${status}. ChatGPT usage service may be unavailable.`;
  return `wham/usage returned HTTP ${status}: ${sanitizeError(String(body || '')).slice(0, 300) || 'No response body.'}`;
}

function curlFailureMessage(code, stderr) {
  const safe = sanitizeError(stderr).trim();
  if (code === 28 || /timed out|timeout/i.test(safe)) return 'Timed out while requesting wham/usage.';
  if (/proxy/i.test(safe)) return `Proxy/network error while requesting wham/usage: ${safe}`;
  return `Unable to request wham/usage: ${safe || `curl exited with ${code}`}`;
}

function parseJwtPayload(token) {
  if (!token || typeof token !== 'string') return undefined;
  const parts = token.split('.');
  if (parts.length !== 3 || parts[1].length > 8192) return undefined;
  try {
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch {
    return undefined;
  }
}

function accountIdFromJwtPayload(payload) {
  const authClaim = isRecord(payload?.[OPENAI_AUTH_CLAIM]) ? payload[OPENAI_AUTH_CLAIM] : undefined;
  return stringValue(authClaim?.chatgpt_account_id) ?? stringValue(payload?.chatgpt_account_id);
}

function maskIdentifier(value) {
  if (value.length <= 8) return '[present]';
  return `${value.slice(0, 4)}...${value.slice(-4)}`;
}

function sanitizeError(value) {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
    .replace(/(access[_-]?token|refresh[_-]?token|authorization|cookie|secret|credential)["'\s:=]+[^"'\s,}]+/gi, '$1=[REDACTED]')
    .trim();
}

function numberFrom(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value);
  return undefined;
}

function stringValue(value) {
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
