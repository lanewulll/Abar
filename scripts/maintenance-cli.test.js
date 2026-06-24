import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const cliPath = new URL('./abar-maintenance.js', import.meta.url).pathname;

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'abar-maintenance-cli-'));
  const home = path.join(root, 'home');
  const codexHome = path.join(home, '.codex');
  const installDir = path.join(home, 'Applications');
  const reporter = path.join(installDir, 'Abar.app', 'Contents', 'Resources', 'reporter', 'reporter.js');
  fs.mkdirSync(path.dirname(reporter), { recursive: true });
  fs.writeFileSync(reporter, '// reporter');
  return { root, home, codexHome, installDir, reporter };
}

function run(args, values) {
  return spawnSync(process.execPath, [cliPath, ...args], {
    encoding: 'utf8',
    env: {
      ...process.env,
      HOME: values.home,
      CODEX_HOME: values.codexHome,
      ABAR_INSTALL_DIR: values.installDir,
      ABAR_CURRENT_COMMIT: 'abc123',
      ABAR_LATEST_COMMIT: 'def456'
    }
  });
}

test('hooks install backs up and merges valid user configuration', () => {
  const values = fixture();
  fs.mkdirSync(values.codexHome, { recursive: true });
  const hooksPath = path.join(values.codexHome, 'hooks.json');
  fs.writeFileSync(hooksPath, JSON.stringify({
    hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo keep-me' }] }] }
  }));

  const result = run(['hooks', 'install'], values);
  assert.equal(result.status, 0, result.stderr);
  const merged = JSON.parse(fs.readFileSync(hooksPath, 'utf8'));
  assert.equal(merged.hooks.Stop[0].hooks[0].command, 'echo keep-me');
  assert.match(merged.hooks.Stop[1].hooks[0].command, /ABAR_HOOK_OWNER=abar-v1/);
  assert.ok(fs.readdirSync(values.codexHome).some((name) => name.startsWith('hooks.json.abar-backup-')));
});

test('hooks install refuses invalid JSON without replacing it', () => {
  const values = fixture();
  fs.mkdirSync(values.codexHome, { recursive: true });
  const hooksPath = path.join(values.codexHome, 'hooks.json');
  fs.writeFileSync(hooksPath, '{ invalid');

  const result = run(['hooks', 'install'], values);
  assert.notEqual(result.status, 0);
  assert.equal(fs.readFileSync(hooksPath, 'utf8'), '{ invalid');
  assert.match(result.stderr, /无效 JSON/);
});

test('full uninstall dry run keeps files while execute removes owned state', () => {
  const values = fixture();
  const dataDir = path.join(values.home, 'Library', 'Application Support', 'abar');
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'abar.sqlite'), 'db');
  fs.mkdirSync(values.codexHome, { recursive: true });
  fs.writeFileSync(path.join(values.codexHome, 'hooks.json'), JSON.stringify({
    hooks: {
      Stop: [
        { hooks: [{ type: 'command', command: 'ABAR_HOOK_OWNER=abar-v1 node reporter.js' }] },
        { hooks: [{ type: 'command', command: 'echo keep-me' }] }
      ]
    }
  }));

  const preview = run(['uninstall', 'full', '--dry-run'], values);
  assert.equal(preview.status, 0, preview.stderr);
  assert.ok(fs.existsSync(dataDir));

  const execute = run(['uninstall', 'full', '--yes'], values);
  assert.equal(execute.status, 0, execute.stderr);
  assert.equal(fs.existsSync(dataDir), false);
  const hooks = JSON.parse(fs.readFileSync(path.join(values.codexHome, 'hooks.json'), 'utf8'));
  assert.equal(hooks.hooks.Stop.length, 1);
  assert.equal(hooks.hooks.Stop[0].hooks[0].command, 'echo keep-me');
});

test('app-only uninstall removes app and preserves data and hooks', () => {
  const values = fixture();
  const dataDir = path.join(values.home, 'Library', 'Application Support', 'abar');
  fs.mkdirSync(dataDir, { recursive: true });
  fs.mkdirSync(values.codexHome, { recursive: true });
  const hooksPath = path.join(values.codexHome, 'hooks.json');
  fs.writeFileSync(hooksPath, JSON.stringify({ hooks: { Stop: [] } }));

  const result = run(['uninstall', 'app', '--yes'], values);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.existsSync(path.join(values.installDir, 'Abar.app')), false);
  assert.equal(fs.existsSync(dataDir), true);
  assert.equal(fs.existsSync(hooksPath), true);
});

test('update check supports deterministic commit inputs', () => {
  const values = fixture();
  const result = run(['update', 'check', '--json'], values);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).status, 'available');
});
