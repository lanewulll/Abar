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
});
