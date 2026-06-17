import { lstat, readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { QuotaSnapshot, UsageWindow } from '../types';
import { resolveCodexHome } from './codexAuth';

const MAX_JSONL_FILE_SIZE = 10 * 1024 * 1024;
const MAX_FILES_TO_SCAN = 50;

export type LocalRateLimitEstimateOptions = {
  codexHome?: string;
};

type CandidateFile = {
  path: string;
  mtimeMs: number;
};

export async function readLocalCodexRateLimitEstimate(
  options: LocalRateLimitEstimateOptions = {}
): Promise<QuotaSnapshot | undefined> {
  const codexHome = resolveCodexHome({ codexHome: options.codexHome });
  const sessionsDir = join(codexHome, 'sessions');
  const candidates = await collectRecentRolloutFiles(sessionsDir);

  for (const candidate of candidates.slice(0, MAX_FILES_TO_SCAN)) {
    const windows = await readWindowsFromSessionFile(candidate.path);
    if (windows.length > 0) {
      return {
        provider: 'codex',
        source: 'local_estimate',
        confidence: 'low',
        windows,
        updatedAt: new Date(candidate.mtimeMs).toISOString(),
        raw: {
          source: 'codex_session_jsonl',
          file: candidate.path
        }
      };
    }
  }

  return undefined;
}

async function collectRecentRolloutFiles(sessionsDir: string): Promise<CandidateFile[]> {
  if (!(await isDirectory(sessionsDir))) {
    return [];
  }

  const candidates: CandidateFile[] = [];
  await walkSessions(sessionsDir, candidates);
  return candidates.sort((left, right) => right.mtimeMs - left.mtimeMs);
}

async function walkSessions(directory: string, candidates: CandidateFile[]): Promise<void> {
  const entries = await readdir(directory, { withFileTypes: true }).catch(() => []);
  await Promise.all(
    entries.map(async (entry) => {
      const fullPath = join(directory, entry.name);
      if (entry.isDirectory()) {
        if (/^\d{4}$|^\d{2}$/.test(entry.name)) {
          await walkSessions(fullPath, candidates);
        }
        return;
      }

      if (!entry.isFile() || !/^rollout-.*\.jsonl$/.test(entry.name)) {
        return;
      }

      const stat = await lstat(fullPath).catch(() => undefined);
      if (!stat?.isFile() || stat.isSymbolicLink() || stat.size > MAX_JSONL_FILE_SIZE) {
        return;
      }
      candidates.push({ path: fullPath, mtimeMs: stat.mtimeMs });
    })
  );
}

async function readWindowsFromSessionFile(filePath: string): Promise<UsageWindow[]> {
  const text = await readFile(filePath, 'utf8').catch(() => '');
  if (!text) {
    return [];
  }

  const lines = text.split('\n');
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index].trim();
    if (!line) {
      continue;
    }

    const event = parseJsonRecord(line);
    const payload = event?.type === 'event_msg' && isRecord(event.payload) ? event.payload : event;
    if (payload?.type !== 'token_count') {
      continue;
    }

    const rateLimits = isRecord(payload.rate_limits) ? payload.rate_limits : undefined;
    const windows = normalizeLocalRateLimits(rateLimits);
    if (windows.length > 0) {
      return windows;
    }
  }

  return [];
}

function normalizeLocalRateLimits(rateLimits: Record<string, unknown> | undefined): UsageWindow[] {
  if (!rateLimits) {
    return [];
  }

  const windows = [
    normalizeLocalWindow(rateLimits.primary ?? rateLimits.primary_window),
    normalizeLocalWindow(rateLimits.secondary ?? rateLimits.secondary_window)
  ].filter((window): window is UsageWindow => Boolean(window));

  return windows;
}

function normalizeLocalWindow(raw: unknown): UsageWindow | undefined {
  if (!isRecord(raw)) {
    return undefined;
  }

  const usedPercent = numberFrom(raw.used_percent ?? raw.usedPercent ?? raw.utilization);
  const windowSeconds =
    numberFrom(raw.limit_window_seconds ?? raw.limitWindowSeconds) ??
    numberFrom(raw.window_seconds ?? raw.windowSeconds) ??
    minutesToSeconds(numberFrom(raw.window_minutes ?? raw.windowMinutes));
  const resetsAt = normalizeResetAt(raw.reset_at ?? raw.resets_at ?? raw.resetAt ?? raw.resetsAt);
  const resetInSeconds = numberFrom(raw.reset_after_seconds ?? raw.resets_in_seconds ?? raw.resetInSeconds);

  if (usedPercent === undefined && windowSeconds === undefined && !resetsAt && resetInSeconds === undefined) {
    return undefined;
  }

  return {
    name: windowNameFromSeconds(windowSeconds),
    ...(usedPercent !== undefined ? { usedPercent: clampPercent(usedPercent), remainingPercent: clampPercent(100 - usedPercent) } : {}),
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

function normalizeResetAt(value: unknown): string | undefined {
  const numeric = numberFrom(value);
  if (numeric !== undefined) {
    const millis = numeric > 1_000_000_000_000 ? numeric : numeric * 1000;
    return new Date(millis).toISOString();
  }

  if (typeof value === 'string' && value.trim()) {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
  }

  return undefined;
}

function minutesToSeconds(minutes: number | undefined): number | undefined {
  return minutes === undefined ? undefined : minutes * 60;
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

function parseJsonRecord(line: string): Record<string, unknown> | undefined {
  try {
    const parsed = JSON.parse(line);
    return isRecord(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

async function isDirectory(path: string): Promise<boolean> {
  const stat = await lstat(path).catch(() => undefined);
  return Boolean(stat?.isDirectory() && !stat.isSymbolicLink());
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
