import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  ABAR_HOOK_MARKER,
  buildAbarHookConfig,
  mergeAbarHooks,
  removeOwnedAbarHooks
} from './lib/hook-config.js';
import { redactDiagnosticValue } from './lib/diagnostic.js';
import { buildFullUninstallPlan } from './lib/uninstall.js';
import { compareUpdateState } from './lib/update-check.js';

test('mergeAbarHooks preserves user hooks and replaces legacy Abar hooks', () => {
  const existing = {
    hooks: {
      Stop: [
        { hooks: [{ type: 'command', command: 'echo user-hook' }] },
        {
          hooks: [{
            type: 'command',
            command: "node '/tmp/Abar/reporters/codex-hook-reporter/reporter.js'"
          }]
        }
      ]
    },
    custom: { keep: true }
  };

  const merged = mergeAbarHooks(existing, buildAbarHookConfig('/Applications/Abar Reporter/reporter.js', 3987));

  assert.equal(merged.custom.keep, true);
  assert.equal(merged.hooks.Stop.length, 2);
  assert.equal(merged.hooks.Stop[0].hooks[0].command, 'echo user-hook');
  assert.match(merged.hooks.Stop[1].hooks[0].command, new RegExp(ABAR_HOOK_MARKER));
  assert.match(merged.hooks.Stop[1].hooks[0].command, /Abar Reporter/);
});

test('removeOwnedAbarHooks removes only marked hooks and reports legacy entries', () => {
  const config = {
    hooks: {
      UserPromptSubmit: [
        buildAbarHookConfig('/tmp/reporter.js', 3987).hooks.UserPromptSubmit[0],
        { hooks: [{ type: 'command', command: 'echo user-hook' }] }
      ],
      Stop: [{
        hooks: [{
          type: 'command',
          command: "node '/tmp/Abar/reporters/codex-hook-reporter/reporter.js'"
        }]
      }]
    }
  };

  const result = removeOwnedAbarHooks(config);

  assert.equal(result.config.hooks.UserPromptSubmit.length, 1);
  assert.equal(result.config.hooks.UserPromptSubmit[0].hooks[0].command, 'echo user-hook');
  assert.equal(result.config.hooks.Stop.length, 1);
  assert.equal(result.legacyEntries.length, 1);
});

test('redactDiagnosticValue replaces home directory and sensitive values', () => {
  const home = '/Users/example';
  const value = {
    path: '/Users/example/Library/Application Support/abar/abar.sqlite',
    access_token: 'secret-token',
    nested: { authorization: 'Bearer private', prompt: 'do not include this' },
    detail: 'login user@example.com failed with Bearer abc.def'
  };

  assert.deepEqual(redactDiagnosticValue(value, home), {
    path: '~/Library/Application Support/abar/abar.sqlite',
    access_token: '[redacted]',
    nested: { authorization: '[redacted]', prompt: '[omitted]' },
    detail: 'login [redacted-email] failed with Bearer [redacted]'
  });
});

test('full uninstall plan includes data and logs without deleting unowned hooks', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'abar-uninstall-'));
  const home = path.join(root, 'home');
  const plan = buildFullUninstallPlan({
    home,
    installDir: path.join(home, 'Applications'),
    codexHome: path.join(home, '.codex')
  });

  assert.equal(plan.mode, 'full');
  assert.ok(plan.paths.some((value) => value.endsWith('/Applications/Abar.app')));
  assert.ok(plan.paths.some((value) => value.endsWith('/Library/Application Support/abar')));
  assert.ok(plan.paths.some((value) => value.endsWith('/Library/Logs/Abar')));
  assert.equal(plan.hooksPath, path.join(home, '.codex', 'hooks.json'));
});

test('compareUpdateState detects newer main commit without treating unknown state as current', () => {
  assert.equal(compareUpdateState({ currentCommit: 'abc', latestCommit: 'def' }).status, 'available');
  assert.equal(compareUpdateState({ currentCommit: 'abc', latestCommit: 'abc' }).status, 'current');
  assert.equal(compareUpdateState({ currentCommit: '', latestCommit: 'def' }).status, 'unknown');
});
