import { describe, expect, it } from 'vitest';
import { normalizeCodexHookPayload } from '../backend/codex/activityAnalyzer';

describe('normalizeCodexHookPayload', () => {
  it('maps Codex PreToolUse hook payloads into stored events', () => {
    const event = normalizeCodexHookPayload({
      hook_event_name: 'PreToolUse',
      session_id: 'session-1',
      cwd: '/tmp/project',
      tool_name: 'Bash',
      tool_use_id: 'tool-1',
      tool_input: {
        command: 'echo hello',
        authorization: 'secret-token'
      }
    });

    expect(event).toMatchObject({
      agent: 'codex',
      eventType: 'PreToolUse',
      projectPath: '/tmp/project',
      sessionId: 'session-1',
      toolName: 'Bash',
      toolUseId: 'tool-1',
      status: 'unknown'
    });
    expect(JSON.stringify(event.payload)).toContain('[REDACTED]');
  });

  it('marks PostToolUse failures from error-like payloads', () => {
    const event = normalizeCodexHookPayload({
      hook_event_name: 'PostToolUse',
      session_id: 'session-1',
      cwd: '/tmp/project',
      tool_name: 'apply_patch',
      tool_use_id: 'tool-2',
      tool_response: {
        error: 'patch failed'
      }
    });

    expect(event.eventType).toBe('PostToolUse');
    expect(event.status).toBe('error');
  });
});
