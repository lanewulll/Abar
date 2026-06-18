import type { AgentRun, CodexEvent, LocalServerStatus, QuotaSnapshot, UsageWindow } from '../../backend/types';

export function formatPercent(value: number | undefined): string {
  return typeof value === 'number' ? `${Math.round(value)}%` : 'Not available';
}

export function formatReset(window: UsageWindow | undefined): string {
  if (!window?.resetsAt) {
    return 'Reset unknown';
  }
  if (typeof window.resetInSeconds === 'number') {
    return `Resets in ${formatDuration(window.resetInSeconds)}`;
  }
  return new Date(window.resetsAt).toLocaleString();
}

export function formatDuration(seconds: number): string {
  const safe = Math.max(0, seconds);
  const days = Math.floor(safe / 86400);
  const hours = Math.floor((safe % 86400) / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  if (days > 0) {
    return `${days}d ${hours}h`;
  }
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
}

export function latestToolCall(events: CodexEvent[]): CodexEvent | undefined {
  return events.find((event) => event.toolName) ?? events[0];
}

export function statusFromEvents(events: CodexEvent[]): 'Active' | 'Idle' | 'Inactive' | 'Not configured' {
  if (events.length === 0) {
    return 'Not configured';
  }
  const latest = new Date(events[0]?.createdAt ?? '').getTime();
  if (!Number.isFinite(latest)) {
    return 'Not configured';
  }
  const ageSeconds = (Date.now() - latest) / 1000;
  if (ageSeconds <= 30) {
    return 'Active';
  }
  if (ageSeconds <= 600) {
    return 'Idle';
  }
  return 'Inactive';
}

export function quotaWindow(snapshot: QuotaSnapshot | undefined, name: '5h' | 'weekly'): UsageWindow | undefined {
  return snapshot?.windows.find((window) => window.name === name);
}

export function shouldShowHookSetup(events: CodexEvent[]): boolean {
  return events.length === 0;
}

export function shouldAutoRefreshQuota(snapshot: QuotaSnapshot | undefined): boolean {
  return snapshot === undefined;
}

export function hookSignalState(
  server: LocalServerStatus,
  events: CodexEvent[]
): { tone: 'ok' | 'waiting' | 'error'; label: string } {
  if (!server.listening || server.error) {
    return { tone: 'error', label: 'Abar server needs attention' };
  }
  if (events.length === 0) {
    return { tone: 'waiting', label: 'Waiting for Codex hook signal' };
  }
  return { tone: 'ok', label: 'Codex hook signal active' };
}

export function quotaRefreshNotice(
  snapshot: QuotaSnapshot,
  silent: boolean
): { tone: 'success' | 'error'; message: string } | null {
  if (silent) {
    return null;
  }
  return snapshot.error
    ? { tone: 'error', message: snapshot.error }
    : { tone: 'success', message: 'Quota refreshed.' };
}

export function noticePlacement(
  notice: { tone: string; message: string } | null
): 'header' | 'content' | 'none' {
  if (!notice) {
    return 'none';
  }
  if (notice.tone === 'success' && notice.message === 'Quota refreshed.') {
    return 'header';
  }
  return 'content';
}

export function mainMetricTiles(
  skillCount: number,
  agentRunCount: number
): Array<{ key: 'skills' | 'events'; label: string; value: string }> {
  return [
    { key: 'skills', label: 'Skills', value: String(skillCount) },
    { key: 'events', label: 'Agent Runs', value: String(agentRunCount) }
  ];
}

export function serverSettingsSummary(
  server: LocalServerStatus
): { tone: 'good' | 'warn'; value: string; detail: string } {
  if (!server.listening) {
    return {
      tone: 'warn',
      value: 'Off',
      detail: server.error ?? server.host
    };
  }
  return {
    tone: 'good',
    value: String(server.port),
    detail: server.host
  };
}

export function recentActivityPreviewEvents(events: CodexEvent[]): CodexEvent[] {
  return events.filter((event) => event.eventType === 'SessionStart' || event.eventType === 'Stop').slice(0, 5);
}

export function formatAgentRunLine(run: AgentRun): string {
  const start = run.startedAt ? `Started ${formatTime(run.startedAt)}` : 'Unknown start';
  const end = run.stoppedAt ? `Stopped ${formatTime(run.stoppedAt)}` : run.status === 'running' ? 'Running' : 'Unknown end';
  return [start, end, run.source].filter(Boolean).join(' -> ');
}

export function formatAgentRunDuration(run: AgentRun): string {
  if (typeof run.durationSeconds === 'number') {
    return formatDuration(run.durationSeconds);
  }
  if (run.startedAt && run.status === 'running') {
    return formatDuration(Math.round((Date.now() - new Date(run.startedAt).getTime()) / 1000));
  }
  return '';
}

export function formatEventTitle(event: CodexEvent): string {
  return event.toolName ? `${event.eventType} ${event.toolName}` : event.eventType;
}

export function formatTime(value: string | undefined): string {
  if (!value) {
    return 'Not available';
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? 'Not available'
    : date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

export function compactPath(value: string | undefined): string {
  if (!value) {
    return 'Not configured';
  }
  const home = value.replace(/^\/Users\/[^/]+/, '~');
  return home.length > 62 ? `...${home.slice(-59)}` : home;
}
