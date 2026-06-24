import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import test from 'node:test';

test('install output only includes task lifecycle hooks', () => {
  const output = execFileSync(process.execPath, ['reporters/codex-hook-reporter/install.js'], {
    cwd: new URL('../..', import.meta.url),
    encoding: 'utf8'
  });
  const config = JSON.parse(output);

  assert.deepEqual(Object.keys(config.hooks).sort(), ['Stop', 'UserPromptSubmit']);
});

test('install uses the default port when ABAR_SERVER_PORT is invalid', () => {
  const output = execFileSync(process.execPath, ['reporters/codex-hook-reporter/install.js'], {
    cwd: new URL('../..', import.meta.url),
    encoding: 'utf8',
    env: { ...process.env, ABAR_SERVER_PORT: 'invalid' }
  });
  const config = JSON.parse(output);
  const command = config.hooks.UserPromptSubmit[0].hooks[0].command;

  assert.match(command, /^ABAR_SERVER_PORT=3987 /);
});
