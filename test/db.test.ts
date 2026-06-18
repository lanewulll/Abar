import { mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';
import { AbarDatabase } from '../backend/db/db';

describe('AbarDatabase', () => {
  it('initializes tables and persists config, events, skills, and quota snapshots', () => {
    const db = new AbarDatabase(join(mkdtempSync(join(tmpdir(), 'abar-db-')), 'abar.sqlite'));

    db.setConfig('project_path', '/tmp/project');
    db.replaceSkills([
      {
        id: 'skill-1',
        name: 'skill-one',
        description: 'Does one thing.',
        path: '/tmp/project/.agents/skills/skill-one',
        source: 'project',
        skillMdPath: '/tmp/project/.agents/skills/skill-one/SKILL.md',
        hasSkillMd: true,
        lastModifiedAt: '2026-06-16T12:00:00.000Z'
      }
    ]);
    db.insertEvent({
      id: 'event-1',
      agent: 'codex',
      eventType: 'SessionStart',
      projectPath: '/tmp/project',
      status: 'unknown',
      payload: { ok: true },
      createdAt: '2026-06-16T12:00:00.000Z'
    });
    db.insertQuotaSnapshot({
      provider: 'codex',
      source: 'manual',
      confidence: 'low',
      windows: [],
      updatedAt: '2026-06-16T12:00:00.000Z',
      error: 'missing provider'
    });

    expect(db.getConfig('project_path')).toBe('/tmp/project');
    expect(db.listSkills()).toHaveLength(1);
    expect(db.listRecentEvents(10)[0]?.eventType).toBe('SessionStart');
    expect(db.getLatestQuotaSnapshot()?.error).toBe('missing provider');

    db.close();
  });

  it('lists recent agent runs from session start and stop events without tool-event noise', () => {
    const db = new AbarDatabase(join(mkdtempSync(join(tmpdir(), 'abar-db-')), 'abar.sqlite'));

    for (let index = 0; index < 60; index += 1) {
      db.insertEvent({
        id: `tool-${index}`,
        agent: 'codex',
        eventType: 'PreToolUse',
        toolName: 'Bash',
        sessionId: 'noise-session',
        createdAt: `2026-06-16T12:${String(index).padStart(2, '0')}:00.000Z`
      });
    }

    db.insertEvent({
      id: 'run-1-start',
      agent: 'codex',
      eventType: 'SessionStart',
      sessionId: 'run-1',
      projectPath: '/tmp/project',
      payload: { source: 'startup' },
      createdAt: '2026-06-16T10:00:00.000Z'
    });
    db.insertEvent({
      id: 'run-1-stop',
      agent: 'codex',
      eventType: 'Stop',
      sessionId: 'run-1',
      projectPath: '/tmp/project',
      createdAt: '2026-06-16T10:45:00.000Z'
    });
    db.insertEvent({
      id: 'run-2-start',
      agent: 'codex',
      eventType: 'SessionStart',
      sessionId: 'run-2',
      projectPath: '/tmp/project',
      payload: { source: 'resume' },
      createdAt: '2026-06-16T11:00:00.000Z'
    });

    expect(db.listRecentAgentRuns(5)).toEqual([
      {
        sessionId: 'run-2',
        projectPath: '/tmp/project',
        startedAt: '2026-06-16T11:00:00.000Z',
        source: 'resume',
        status: 'running',
        lastEventAt: '2026-06-16T11:00:00.000Z'
      },
      {
        sessionId: 'run-1',
        projectPath: '/tmp/project',
        startedAt: '2026-06-16T10:00:00.000Z',
        stoppedAt: '2026-06-16T10:45:00.000Z',
        source: 'startup',
        status: 'stopped',
        durationSeconds: 2700,
        lastEventAt: '2026-06-16T10:45:00.000Z'
      }
    ]);

    db.close();
  });

  it('pairs each session start with the next stop instead of spanning the whole session id', () => {
    const db = new AbarDatabase(join(mkdtempSync(join(tmpdir(), 'abar-db-')), 'abar.sqlite'));

    db.insertEvent({
      id: 'old-start',
      agent: 'codex',
      eventType: 'SessionStart',
      sessionId: 'same-session',
      payload: { source: 'startup' },
      createdAt: '2026-06-16T03:04:27.000Z'
    });
    db.insertEvent({
      id: 'old-stop',
      agent: 'codex',
      eventType: 'Stop',
      sessionId: 'same-session',
      createdAt: '2026-06-16T03:05:19.000Z'
    });
    db.insertEvent({
      id: 'new-start',
      agent: 'codex',
      eventType: 'SessionStart',
      sessionId: 'same-session',
      payload: { source: 'compact' },
      createdAt: '2026-06-16T07:53:21.000Z'
    });
    db.insertEvent({
      id: 'new-stop',
      agent: 'codex',
      eventType: 'Stop',
      sessionId: 'same-session',
      createdAt: '2026-06-16T07:56:21.000Z'
    });

    expect(db.listRecentAgentRuns(5)).toMatchObject([
      {
        sessionId: 'same-session',
        startedAt: '2026-06-16T07:53:21.000Z',
        stoppedAt: '2026-06-16T07:56:21.000Z',
        source: 'compact',
        durationSeconds: 180
      },
      {
        sessionId: 'same-session',
        startedAt: '2026-06-16T03:04:27.000Z',
        stoppedAt: '2026-06-16T03:05:19.000Z',
        source: 'startup',
        durationSeconds: 52
      }
    ]);

    db.close();
  });
});
