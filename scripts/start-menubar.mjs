#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { findAbarProcessIds } from './startMenubarProcessFilter.mjs';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const appPath = resolve(repoRoot, 'dist/mac-arm64/Abar.app');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    stdio: 'inherit',
    shell: false,
    ...options
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function output(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: 'utf8',
    shell: false
  });
  return result.status === 0 ? result.stdout : '';
}

function stopExistingAbar() {
  spawnSync('osascript', ['-e', 'tell application "Abar" to quit'], { stdio: 'ignore' });

  const processList = output('ps', ['-axo', 'pid,command']);
  const killTargets = findAbarProcessIds(processList, repoRoot, process.pid);

  if (killTargets.length > 0) {
    spawnSync('kill', killTargets.map(String), { stdio: 'ignore' });
    spawnSync('kill', ['-9', ...killTargets.map(String)], { stdio: 'ignore' });
  }
}

stopExistingAbar();
run('npm', ['run', 'package:mac']);

if (!existsSync(appPath)) {
  console.error(`[Abar] packaged app not found: ${appPath}`);
  process.exit(1);
}

const child = spawn('open', [appPath], {
  cwd: repoRoot,
  detached: true,
  stdio: 'ignore'
});
child.unref();

console.log(`[Abar] opened menu bar app: ${appPath}`);
