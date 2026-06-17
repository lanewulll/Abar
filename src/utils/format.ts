import type { CodexEvent, QuotaSnapshot, UsageWindow } from '../../backend/types';

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
