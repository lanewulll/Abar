import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const OPENAI_AUTH_CLAIM = 'https://api.openai.com/auth';
const MAX_JWT_LENGTH = 16 * 1024;
const MAX_JWT_PAYLOAD_LENGTH = 8 * 1024;

export type CodexAuthState = {
  authPath: string;
  accessToken?: string;
  refreshToken?: string;
  idToken?: string;
  accountId?: string;
  accountIdSource?: 'auth.json' | 'jwt' | 'none';
  lastRefresh?: string;
  accessTokenExpiresAt?: string;
  hasAccessToken: boolean;
  hasRefreshToken: boolean;
  hasIdToken: boolean;
  hasAccountId: boolean;
  error?: string;
};

export type CodexAuthDiagnostic = Omit<CodexAuthState, 'accessToken' | 'refreshToken' | 'idToken' | 'accountId'> & {
  maskedAccountId?: string;
};

export type ReadCodexAuthStateOptions = {
  codexHome?: string;
  authPath?: string;
  env?: NodeJS.ProcessEnv;
};

export async function readCodexAuthState(options: ReadCodexAuthStateOptions = {}): Promise<CodexAuthState> {
  const authPath = resolveAuthPath(options);

  try {
    const text = await readFile(authPath, 'utf8');
    const json = JSON.parse(text) as unknown;
    return parseCodexAuthJson(json, authPath);
  } catch (error) {
    return {
      authPath,
      hasAccessToken: false,
      hasRefreshToken: false,
      hasIdToken: false,
      hasAccountId: false,
      accountIdSource: 'none',
      error: authReadError(error)
    };
  }
}

export function parseCodexAuthJson(raw: unknown, authPath = 'auth.json'): CodexAuthState {
  const root = isRecord(raw) ? raw : {};
  const tokens = isRecord(root.tokens) ? root.tokens : {};
  const accessToken = stringValue(tokens.access_token) ?? stringValue(tokens.accessToken);
  const refreshToken = stringValue(tokens.refresh_token) ?? stringValue(tokens.refreshToken);
  const idToken = stringValue(tokens.id_token) ?? stringValue(tokens.idToken);
  const explicitAccountId = stringValue(tokens.account_id) ?? stringValue(tokens.accountId);
  const accessPayload = parseJwtPayload(accessToken);
  const idPayload = parseJwtPayload(idToken);
  const jwtAccountId =
    accountIdFromJwtPayload(accessPayload) ??
    accountIdFromJwtPayload(idPayload);
  const accountId = explicitAccountId ?? jwtAccountId;
  const lastRefresh = normalizeIsoDate(root.last_refresh ?? root.lastRefresh);
  const accessTokenExpiresAt = epochSecondsToIso(numberValue(accessPayload?.exp));

  return {
    authPath,
    ...(accessToken ? { accessToken } : {}),
    ...(refreshToken ? { refreshToken } : {}),
    ...(idToken ? { idToken } : {}),
    ...(accountId ? { accountId } : {}),
    accountIdSource: explicitAccountId ? 'auth.json' : jwtAccountId ? 'jwt' : 'none',
    ...(lastRefresh ? { lastRefresh } : {}),
    ...(accessTokenExpiresAt ? { accessTokenExpiresAt } : {}),
    hasAccessToken: Boolean(accessToken),
    hasRefreshToken: Boolean(refreshToken),
    hasIdToken: Boolean(idToken),
    hasAccountId: Boolean(accountId),
    ...(!accessToken ? { error: 'Codex auth.json exists but does not contain tokens.access_token.' } : {})
  };
}

export function sanitizeCodexAuthState(auth: CodexAuthState): CodexAuthDiagnostic {
  const { accessToken, refreshToken, idToken, accountId, ...safe } = auth;
  return {
    ...safe,
    ...(accountId ? { maskedAccountId: maskIdentifier(accountId) } : {})
  };
}

export function resolveCodexHome(options: Pick<ReadCodexAuthStateOptions, 'codexHome' | 'env'> = {}): string {
  const env = options.env ?? process.env;
  const configured = options.codexHome ?? env.CODEX_HOME;
  if (configured?.trim()) {
    return configured;
  }
  return join(homedir(), '.codex');
}

function resolveAuthPath(options: ReadCodexAuthStateOptions): string {
  if (options.authPath?.trim()) {
    return options.authPath;
  }
  return join(resolveCodexHome(options), 'auth.json');
}

function parseJwtPayload(token: string | undefined): Record<string, unknown> | undefined {
  if (!token || token.length > MAX_JWT_LENGTH) {
    return undefined;
  }

  const parts = token.split('.');
  if (parts.length !== 3 || parts[1].length > MAX_JWT_PAYLOAD_LENGTH) {
    return undefined;
  }

  try {
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as Record<string, unknown>;
  } catch {
    return undefined;
  }
}

function accountIdFromJwtPayload(payload: Record<string, unknown> | undefined): string | undefined {
  const authClaim = isRecord(payload?.[OPENAI_AUTH_CLAIM]) ? payload?.[OPENAI_AUTH_CLAIM] : undefined;
  return stringValue(authClaim?.chatgpt_account_id) ?? stringValue(payload?.chatgpt_account_id);
}

function authReadError(error: unknown): string {
  if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
    return 'Codex auth.json not found. Run `codex` and sign in, or configure CODEX_HOME if you use a custom Codex home.';
  }
  if (error instanceof SyntaxError) {
    return `Codex auth.json is not valid JSON: ${error.message}`;
  }
  if (error instanceof Error) {
    return `Unable to read Codex auth.json: ${error.message}`;
  }
  return `Unable to read Codex auth.json: ${String(error)}`;
}

function maskIdentifier(value: string): string {
  if (value.length <= 8) {
    return '[present]';
  }
  return `${value.slice(0, 4)}...${value.slice(-4)}`;
}

function normalizeIsoDate(value: unknown): string | undefined {
  if (typeof value !== 'string' || !value.trim()) {
    return undefined;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toISOString();
}

function epochSecondsToIso(value: number | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  return new Date(value * 1000).toISOString();
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
