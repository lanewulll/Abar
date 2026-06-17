import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('codex-hook-reporter', () => {
  it('exits successfully when Abar local server is unavailable', async () => {
    const result = await runReporter({
      ABAR_SERVER_PORT: '9',
      ABAR_REPORTER_TIMEOUT_MS: '100',
      ABAR_REPORTER_DEBUG: '0'
    });

    expect(result.code).toBe(0);
    expect(result.stdout).toBe('');
  });
});

function runReporter(env: NodeJS.ProcessEnv): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [join(process.cwd(), 'reporters/codex-hook-reporter/reporter.js')], {
      env: { ...process.env, ...env },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('close', (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(
      JSON.stringify({
        hook_event_name: 'SessionStart',
        session_id: 'test',
        cwd: process.cwd()
      })
    );
  });
}
