import { dirname, basename } from 'node:path';
import { mkdirSync } from 'node:fs';
import Database from 'better-sqlite3';
import { schemaSql } from './schema';
import type { AgentRun, CodexEvent, QuotaSnapshot, SkillInfo } from '../types';
import { safeJsonParse, safeJsonStringify } from '../utils/sanitize';

type DbRow = Record<string, unknown>;

export class AbarDatabase {
  private readonly db: Database.Database;

  constructor(dbPath: string) {
    mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath);
    this.db.pragma('journal_mode = WAL');
    this.db.exec(schemaSql);
  }

  close(): void {
    this.db.close();
  }

  getConfig(key: string): string | undefined {
    const row = this.db.prepare('SELECT value FROM app_config WHERE key = ?').get(key) as DbRow | undefined;
    return typeof row?.value === 'string' ? row.value : undefined;
  }

  setConfig(key: string, value: string): void {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO app_config (key, value, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
      )
      .run(key, value, now);
  }

  getProjectPath(): string | undefined {
    return this.getConfig('project_path');
  }

  setProjectPath(projectPath: string): void {
    const now = new Date().toISOString();
    this.setConfig('project_path', projectPath);
    this.db.prepare('UPDATE projects SET is_active = 0, updated_at = ?').run(now);
    this.db
      .prepare(
        `INSERT INTO projects (id, name, path, is_active, created_at, updated_at)
         VALUES (?, ?, ?, 1, ?, ?)
         ON CONFLICT(path) DO UPDATE SET name = excluded.name, is_active = 1, updated_at = excluded.updated_at`
      )
      .run(stableProjectId(projectPath), basename(projectPath), projectPath, now, now);
  }

  replaceSkills(skills: SkillInfo[]): void {
    const scannedAt = new Date().toISOString();
    const transaction = this.db.transaction((items: SkillInfo[]) => {
      this.db.prepare('DELETE FROM skills').run();
      const insert = this.db.prepare(
        `INSERT INTO skills (
          id, project_id, name, description, path, source, skill_md_path,
          has_skill_md, last_modified_at, scanned_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      );
      for (const skill of items) {
        insert.run(
          skill.id,
          null,
          skill.name,
          skill.description,
          skill.path,
          skill.source,
          skill.skillMdPath,
          skill.hasSkillMd ? 1 : 0,
          skill.lastModifiedAt ?? null,
          scannedAt
        );
      }
    });
    transaction(skills);
  }

  listSkills(): SkillInfo[] {
    const rows = this.db
      .prepare(
        `SELECT id, name, description, path, source, skill_md_path, has_skill_md, last_modified_at
         FROM skills
         ORDER BY CASE source WHEN 'project' THEN 0 WHEN 'user' THEN 1 WHEN 'system' THEN 2 ELSE 3 END, name`
      )
      .all() as DbRow[];

    return rows.map((row) => ({
      id: String(row.id),
      name: String(row.name),
      description: String(row.description),
      path: String(row.path),
      source: row.source as SkillInfo['source'],
      skillMdPath: String(row.skill_md_path),
      hasSkillMd: Boolean(row.has_skill_md),
      ...(typeof row.last_modified_at === 'string' ? { lastModifiedAt: row.last_modified_at } : {})
    }));
  }

  insertEvent(event: CodexEvent): void {
    this.db
      .prepare(
        `INSERT INTO events (
          id, agent, event_type, project_path, session_id, tool_name,
          tool_use_id, status, payload_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        event.id,
        event.agent,
        event.eventType,
        event.projectPath ?? null,
        event.sessionId ?? null,
        event.toolName ?? null,
        event.toolUseId ?? null,
        event.status ?? 'unknown',
        safeJsonStringify(event.payload ?? {}),
        event.createdAt
      );
  }

  listRecentEvents(limit: number): CodexEvent[] {
    const rows = this.db
      .prepare(
        `SELECT id, agent, event_type, project_path, session_id, tool_name,
                tool_use_id, status, payload_json, created_at
         FROM events
         ORDER BY created_at DESC
         LIMIT ?`
      )
      .all(limit) as DbRow[];

    return rows.map((row) => ({
      id: String(row.id),
      agent: 'codex',
      eventType: String(row.event_type) as CodexEvent['eventType'],
      ...(typeof row.project_path === 'string' ? { projectPath: row.project_path } : {}),
      ...(typeof row.session_id === 'string' ? { sessionId: row.session_id } : {}),
      ...(typeof row.tool_name === 'string' ? { toolName: row.tool_name } : {}),
      ...(typeof row.tool_use_id === 'string' ? { toolUseId: row.tool_use_id } : {}),
      status:
        row.status === 'success' || row.status === 'error' || row.status === 'unknown'
          ? row.status
          : 'unknown',
      payload: safeJsonParse(String(row.payload_json ?? '{}'), {}),
      createdAt: String(row.created_at)
    }));
  }

  listRecentAgentRuns(limit: number): AgentRun[] {
    const rows = this.db
      .prepare(
        `SELECT event_type, project_path, session_id, payload_json, created_at
         FROM events
         WHERE event_type IN ('SessionStart', 'Stop')
           AND session_id IS NOT NULL
         ORDER BY created_at ASC`
      )
      .all() as DbRow[];

    const runs: AgentRun[] = [];
    const openRuns = new Map<string, AgentRun>();
    for (const row of rows) {
      const sessionId = String(row.session_id);
      const eventType = String(row.event_type);
      const createdAt = String(row.created_at);
      const projectPath = typeof row.project_path === 'string' ? row.project_path : undefined;

      if (eventType === 'SessionStart') {
        const previousOpenRun = openRuns.get(sessionId);
        if (previousOpenRun) {
          runs.push(finalizeAgentRun(previousOpenRun));
        }
        const payload = safeJsonParse<Record<string, unknown>>(String(row.payload_json ?? '{}'), {});
        openRuns.set(sessionId, {
          sessionId,
          ...(projectPath ? { projectPath } : {}),
          startedAt: createdAt,
          ...(typeof payload.source === 'string' ? { source: payload.source } : {}),
          status: 'running',
          lastEventAt: createdAt
        });
        continue;
      }

      const openRun = openRuns.get(sessionId);
      if (openRun) {
        openRuns.delete(sessionId);
        runs.push(
          finalizeAgentRun({
            ...openRun,
            ...(openRun.projectPath || !projectPath ? {} : { projectPath }),
            stoppedAt: createdAt,
            lastEventAt: createdAt
          })
        );
        continue;
      }

      runs.push(
        finalizeAgentRun({
          sessionId,
          ...(projectPath ? { projectPath } : {}),
          stoppedAt: createdAt,
          status: 'unknown',
          lastEventAt: createdAt
        })
      );
    }

    runs.push(...[...openRuns.values()].map((run) => finalizeAgentRun(run)));

    return runs.sort((left, right) => right.lastEventAt.localeCompare(left.lastEventAt)).slice(0, limit);
  }

  insertQuotaSnapshot(snapshot: QuotaSnapshot): void {
    this.db
      .prepare(
        `INSERT INTO quota_snapshots (provider, source, confidence, snapshot_json, error, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .run(
        snapshot.provider,
        snapshot.source,
        snapshot.confidence,
        safeJsonStringify(snapshot),
        snapshot.error ?? null,
        new Date().toISOString()
      );
  }

  getLatestQuotaSnapshot(): QuotaSnapshot | undefined {
    const row = this.db
      .prepare('SELECT snapshot_json FROM quota_snapshots ORDER BY created_at DESC LIMIT 1')
      .get() as DbRow | undefined;
    if (typeof row?.snapshot_json !== 'string') {
      return undefined;
    }
    return safeJsonParse<QuotaSnapshot | undefined>(row.snapshot_json, undefined);
  }
}

function stableProjectId(projectPath: string): string {
  return Buffer.from(projectPath).toString('base64url');
}

function finalizeAgentRun(run: AgentRun): AgentRun {
  const status = run.stoppedAt ? 'stopped' : run.startedAt ? 'running' : 'unknown';
  const durationSeconds =
    run.startedAt && run.stoppedAt
      ? Math.max(0, Math.round((new Date(run.stoppedAt).getTime() - new Date(run.startedAt).getTime()) / 1000))
      : undefined;
  return {
    ...run,
    status,
    ...(typeof durationSeconds === 'number' && Number.isFinite(durationSeconds) ? { durationSeconds } : {})
  };
}
