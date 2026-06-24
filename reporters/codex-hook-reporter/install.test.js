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
