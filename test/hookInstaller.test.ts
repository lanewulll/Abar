import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { generateHookInstallPrompt, installCodexHooks } from '../backend/codex/hookInstaller';

const tempDirs: string[] = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function tempHome(): string {
  const dir = mkdtempSync(join(tmpdir(), 'abar-hooks-'));
  tempDirs.push(dir);
  return dir;
}

describe('installCodexHooks', () => {
  it('creates ~/.codex/hooks.json with Abar hooks when missing', () => {
    const homePath = tempHome();
    const result = installCodexHooks({
      homePath,
      reporterPath: '/Applications/Abar.app/Contents/Resources/app.asar.unpacked/reporters/codex-hook-reporter/reporter.js',
      port: 3987,
      eventSecret: 'secret-1'
    });

    expect(result.status).toBe('installed');
    expect(result.targetFile).toBe(join(homePath, '.codex', 'hooks.json'));
    expect(result.backupFile).toBeUndefined();

    const written = JSON.parse(readFileSync(result.targetFile, 'utf8'));
    expect(written.hooks.PreToolUse[0].hooks[0].command).toContain('ABAR_SERVER_PORT=3987');
    expect(written.hooks.PreToolUse[0].hooks[0].command).toContain("ABAR_EVENT_SECRET='secret-1'");
  });

  it('preserves existing non-Abar hooks and writes a backup before modifying', () => {
    const homePath = tempHome();
    const hooksPath = join(homePath, '.codex', 'hooks.json');
    mkdirSync(join(homePath, '.codex'), { recursive: true });
    writeFileSync(
      hooksPath,
      `${JSON.stringify(
        {
          hooks: {
            PreToolUse: [
              {
                matcher: '*',
                hooks: [{ type: 'command', command: 'echo existing', timeout: 1 }]
              }
            ]
          }
        },
        null,
        2
      )}\n`
    );

    const result = installCodexHooks({
      homePath,
      reporterPath: '/repo/reporters/codex-hook-reporter/reporter.js',
      port: 3987
    });

    expect(result.status).toBe('installed');
    expect(result.backupFile).toBe(`${hooksPath}.abar-backup`);
    expect(readFileSync(result.backupFile!, 'utf8')).toContain('echo existing');

    const written = JSON.parse(readFileSync(hooksPath, 'utf8'));
    expect(written.hooks.PreToolUse[0].hooks[0].command).toBe('echo existing');
    expect(written.hooks.PreToolUse[1].hooks[0].command).toContain('codex-hook-reporter/reporter.js');
  });

  it('is idempotent when the current Abar command is already installed', () => {
    const homePath = tempHome();
    const first = installCodexHooks({
      homePath,
      reporterPath: '/repo/reporters/codex-hook-reporter/reporter.js',
      port: 3987
    });
    const second = installCodexHooks({
      homePath,
      reporterPath: '/repo/reporters/codex-hook-reporter/reporter.js',
      port: 3987
    });

    expect(first.status).toBe('installed');
    expect(second.status).toBe('unchanged');

    const written = readFileSync(second.targetFile, 'utf8');
    expect(written.match(/codex-hook-reporter\/reporter\.js/g)?.length).toBe(7);
  });

  it('updates an older Abar hook command instead of appending duplicates', () => {
    const homePath = tempHome();
    installCodexHooks({
      homePath,
      reporterPath: '/old/reporters/codex-hook-reporter/reporter.js',
      port: 3987
    });

    const result = installCodexHooks({
      homePath,
      reporterPath: '/new/reporters/codex-hook-reporter/reporter.js',
      port: 3999
    });

    expect(result.status).toBe('updated');
    const written = readFileSync(result.targetFile, 'utf8');
    expect(written).not.toContain('/old/reporters');
    expect(written.match(/codex-hook-reporter\/reporter\.js/g)?.length).toBe(7);
    expect(written).toContain('ABAR_SERVER_PORT=3999');
  });
});

describe('generateHookInstallPrompt', () => {
  it('creates a pasteable Codex instruction instead of raw hook JSON', () => {
    const prompt = generateHookInstallPrompt({
      homePath: '/Users/lane',
      reporterPath: '/Applications/Abar.app/Contents/Resources/app.asar.unpacked/reporters/codex-hook-reporter/reporter.js',
      port: 3987,
      eventSecret: 'secret-1'
    });

    expect(prompt.targetFile).toBe('/Users/lane/.codex/hooks.json');
    expect(prompt.promptText).toContain('请帮我安装 Abar 的 Codex hooks');
    expect(prompt.promptText).toContain('/Users/lane/.codex/hooks.json');
    expect(prompt.promptText).toContain('ABAR_SERVER_PORT=3987');
    expect(prompt.promptText).toContain("ABAR_EVENT_SECRET='secret-1'");
    expect(prompt.promptText).toContain('保留现有 hooks');
    expect(prompt.promptText).toContain('去重');
    expect(prompt.promptText).toContain('/hooks');
    expect(prompt.promptText).toContain('trust');
    expect(prompt.promptText).toContain('不能替我完成 trust');
    expect(prompt.promptText).toContain('我需要亲自在 /hooks 里 review 并 trust');
  });
});
