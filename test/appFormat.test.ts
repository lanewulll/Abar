import { describe, expect, it } from 'vitest';
import type { AgentRun, CodexEvent, LocalServerStatus, QuotaSnapshot } from '../backend/types';
import {
  formatAgentRunDuration,
  formatAgentRunLine,
  hookSignalState,
  mainMetricTiles,
  noticePlacement,
  quotaRefreshNotice,
  recentActivityPreviewEvents,
  serverSettingsSummary,
  shouldAutoRefreshQuota,
  shouldShowHookSetup
} from '../src/utils/format';

describe('app setup helpers', () => {
  it('hides the hook setup panel after Codex hook events arrive', () => {
    const events: CodexEvent[] = [
      {
        id: 'event-1',
        agent: 'codex',
        eventType: 'PostToolUse',
        toolName: 'Bash',
        createdAt: new Date().toISOString()
      }
    ];

    expect(shouldShowHookSetup(events)).toBe(false);
  });

  it('auto-refreshes quota only when no quota snapshot has been stored', () => {
    const snapshot: QuotaSnapshot = {
      provider: 'codex',
      source: 'internal_web_api',
      confidence: 'high',
      windows: [],
      updatedAt: new Date().toISOString()
    };

    expect(shouldAutoRefreshQuota(undefined)).toBe(true);
    expect(shouldAutoRefreshQuota(snapshot)).toBe(false);
  });

  it('uses red, yellow, and green signal states for hook health', () => {
    const listeningServer: LocalServerStatus = { listening: true, host: '127.0.0.1', port: 3987 };
    const brokenServer: LocalServerStatus = {
      listening: false,
      host: '127.0.0.1',
      port: 3987,
      error: 'port unavailable'
    };
    const events: CodexEvent[] = [
      {
        id: 'event-1',
        agent: 'codex',
        eventType: 'PostToolUse',
        createdAt: new Date().toISOString()
      }
    ];

    expect(hookSignalState(brokenServer, events)).toMatchObject({ tone: 'error' });
    expect(hookSignalState(listeningServer, [])).toMatchObject({ tone: 'waiting' });
    expect(hookSignalState(listeningServer, events)).toMatchObject({ tone: 'ok' });
  });

  it('does not show a quota notice for silent automatic refreshes', () => {
    const snapshot: QuotaSnapshot = {
      provider: 'codex',
      source: 'internal_web_api',
      confidence: 'high',
      windows: [],
      updatedAt: new Date().toISOString()
    };

    expect(quotaRefreshNotice(snapshot, true)).toBeNull();
    expect(quotaRefreshNotice(snapshot, false)).toMatchObject({ tone: 'success', message: 'Quota refreshed.' });
    expect(quotaRefreshNotice({ ...snapshot, error: 'quota failed' }, false)).toMatchObject({
      tone: 'error',
      message: 'quota failed'
    });
  });

  it('places successful quota refresh notices in the compact header area', () => {
    expect(noticePlacement({ tone: 'success', message: 'Quota refreshed.' })).toBe('header');
    expect(noticePlacement({ tone: 'error', message: 'quota failed' })).toBe('content');
    expect(noticePlacement(null)).toBe('none');
  });

  it('uses agent runs for the second metric tile', () => {
    expect(mainMetricTiles(65, 5)).toEqual([
      { key: 'skills', label: 'Skills', value: '65' },
      { key: 'events', label: 'Agent Runs', value: '5' }
    ]);
  });

  it('summarizes server status for the settings panel', () => {
    expect(serverSettingsSummary({ listening: true, host: '127.0.0.1', port: 3987 })).toEqual({
      tone: 'good',
      value: '3987',
      detail: '127.0.0.1'
    });
    expect(serverSettingsSummary({ listening: false, host: '127.0.0.1', port: 3987, error: 'busy' })).toEqual({
      tone: 'warn',
      value: 'Off',
      detail: 'busy'
    });
  });

  it('shows only session start and stop events in the activity preview', () => {
    const events: CodexEvent[] = [
      'PostToolUse',
      'Stop',
      'PreToolUse',
      'SessionStart',
      'UserPromptSubmit',
      'Stop',
      'SessionStart'
    ].map((eventType, index) => ({
      id: `event-${index}`,
      agent: 'codex',
      eventType: eventType as CodexEvent['eventType'],
      createdAt: new Date().toISOString()
    }));

    expect(recentActivityPreviewEvents(events)).toHaveLength(4);
    expect(recentActivityPreviewEvents(events).map((event) => event.id)).toEqual([
      'event-1',
      'event-3',
      'event-5',
      'event-6'
    ]);
  });

  it('formats stopped, running, and unknown-start agent run lines', () => {
    const stopped: AgentRun = {
      sessionId: 'run-1',
      startedAt: '2026-06-18T08:00:00.000Z',
      stoppedAt: '2026-06-18T08:46:30.000Z',
      source: 'startup',
      status: 'stopped',
      durationSeconds: 2790,
      lastEventAt: '2026-06-18T08:46:30.000Z'
    };
    const running: AgentRun = {
      sessionId: 'run-2',
      startedAt: '2026-06-18T09:00:00.000Z',
      source: 'resume',
      status: 'running',
      lastEventAt: '2026-06-18T09:00:00.000Z'
    };
    const unknown: AgentRun = {
      sessionId: 'run-3',
      stoppedAt: '2026-06-18T10:00:00.000Z',
      status: 'stopped',
      lastEventAt: '2026-06-18T10:00:00.000Z'
    };

    expect(formatAgentRunLine(stopped)).toContain('Started');
    expect(formatAgentRunLine(stopped)).toContain('Stopped');
    expect(formatAgentRunLine(stopped)).toContain('startup');
    expect(formatAgentRunDuration(stopped)).toBe('46m');
    expect(formatAgentRunLine(running)).toContain('Running');
    expect(formatAgentRunLine(unknown)).toContain('Unknown start');
  });
});
