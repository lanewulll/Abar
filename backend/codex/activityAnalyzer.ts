import { randomUUID } from 'node:crypto';
import type { ActivityStatus, CodexEvent, CodexEventType } from '../types';
import { redactSensitive } from '../utils/sanitize';

const KNOWN_EVENTS = new Set<CodexEventType>([
  'SessionStart',
  'SessionEnd',
  'PreToolUse',
  'PostToolUse',
  'UserPromptSubmit',
  'Stop',
  'SubagentStart',
  'SubagentStop'
]);

export function normalizeCodexHookPayload(payload: unknown, now = new Date()): CodexEvent {
  const record = asRecord(payload);
  const eventName = stringFrom(record.hook_event_name ?? record.eventType ?? record.event_type);
  const eventType = normalizeEventType(eventName);

  return {
    id: stringFrom(record.id) ?? randomUUID(),
    agent: 'codex',
    eventType,
    ...(stringFrom(record.cwd ?? record.projectPath ?? record.project_path)
      ? { projectPath: stringFrom(record.cwd ?? record.projectPath ?? record.project_path) }
      : {}),
    ...(stringFrom(record.session_id ?? record.sessionId) ? { sessionId: stringFrom(record.session_id ?? record.sessionId) } : {}),
    ...(stringFrom(record.tool_name ?? record.toolName ?? record.agent_type)
      ? { toolName: stringFrom(record.tool_name ?? record.toolName ?? record.agent_type) }
      : {}),
    ...(stringFrom(record.tool_use_id ?? record.toolUseId)
      ? { toolUseId: stringFrom(record.tool_use_id ?? record.toolUseId) }
      : {}),
    status: normalizeStatus(record, eventType),
    payload: redactSensitive(payload),
    createdAt: normalizeCreatedAt(record.createdAt ?? record.created_at, now)
  };
}

export function deriveActivityStatus(events: CodexEvent[], now = new Date()): ActivityStatus {
  if (events.length === 0) {
    return 'Not configured';
  }

  const latest = events
    .map((event) => new Date(event.createdAt).getTime())
    .filter((time) => Number.isFinite(time))
    .sort((left, right) => right - left)[0];

  if (!latest) {
    return 'Not configured';
  }

  const ageSeconds = (now.getTime() - latest) / 1000;
  if (ageSeconds <= 30) {
    return 'Active';
  }
  if (ageSeconds <= 600) {
    return 'Idle';
  }
  return 'Inactive';
}

function normalizeEventType(eventName: string | undefined): CodexEventType {
  if (eventName && KNOWN_EVENTS.has(eventName as CodexEventType)) {
    return eventName as CodexEventType;
  }
  return 'Unknown';
}

function normalizeStatus(
  record: Record<string, unknown>,
  eventType: CodexEventType
): 'success' | 'error' | 'unknown' {
  const explicit = stringFrom(record.status);
  if (explicit === 'success' || explicit === 'error' || explicit === 'unknown') {
    return explicit;
  }

  const response = asRecord(record.tool_response ?? record.toolResponse ?? record.response);
  if (response.error || record.error) {
    return 'error';
  }

  if (eventType === 'PostToolUse') {
    return 'success';
  }

  return 'unknown';
}

function normalizeCreatedAt(value: unknown, fallback: Date): string {
  if (typeof value === 'string' || typeof value === 'number') {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString();
    }
  }
  return fallback.toISOString();
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function stringFrom(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined;
}
