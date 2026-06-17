import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { resolveTrayIconPath } from '../electron/trayAssets';

describe('resolveTrayIconPath', () => {
  it('uses the source asset path in development', () => {
    expect(
      resolveTrayIconPath({
        isPackaged: false,
        appPath: '/repo/Abar',
        resourcesPath: '/repo/Abar/node_modules/electron/dist/Electron.app/Contents/Resources'
      })
    ).toBe(join('/repo/Abar', 'electron', 'assets', 'trayTemplate.png'));
  });

  it('uses the copied resource path when packaged', () => {
    expect(
      resolveTrayIconPath({
        isPackaged: true,
        appPath: '/Applications/Abar.app/Contents/Resources/app.asar',
        resourcesPath: '/Applications/Abar.app/Contents/Resources'
      })
    ).toBe(join('/Applications/Abar.app/Contents/Resources', 'trayTemplate.png'));
  });
});
