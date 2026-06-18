import { describe, expect, it } from 'vitest';
import { findAbarProcessIds } from '../scripts/startMenubarProcessFilter.mjs';

describe('findAbarProcessIds', () => {
  it('matches packaged Abar app processes from this repository', () => {
    const repoRoot = '/Users/lane/Desktop/codex/Abar';
    const processList = [
      ' 42264 /Users/lane/Desktop/codex/Abar/dist/mac-arm64/Abar.app/Contents/MacOS/Abar',
      ' 42335 /Users/lane/Desktop/codex/Abar/dist/mac-arm64/Abar.app/Contents/Frameworks/Abar Helper.app/Contents/MacOS/Abar Helper --type=gpu-process',
      ' 99999 /Applications/Abar.app/Contents/MacOS/Abar'
    ].join('\n');

    expect(findAbarProcessIds(processList, repoRoot, 11111)).toEqual([42264, 42335]);
  });

  it('continues matching raw Electron dev processes from this repository', () => {
    const repoRoot = '/Users/lane/Desktop/codex/Abar';
    const processList = [
      ` 10101 npm run dev:electron ${repoRoot}`,
      ` 20202 node_modules/electron/dist/Electron.app/Contents/MacOS/Electron . ${repoRoot}`,
      ` 30303 electron-vite dev ${repoRoot}`,
      ' 40404 /Users/lane/Desktop/codex/Other/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron .'
    ].join('\n');

    expect(findAbarProcessIds(processList, repoRoot, 11111)).toEqual([10101, 20202, 30303]);
  });
});
