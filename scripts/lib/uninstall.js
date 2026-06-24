import path from 'node:path';

export function buildFullUninstallPlan({ home, installDir, codexHome }) {
  return {
    mode: 'full',
    paths: [
      path.join(installDir, 'Abar.app'),
      path.join(home, 'Library', 'Application Support', 'abar'),
      path.join(home, 'Library', 'Logs', 'Abar'),
      path.join(home, 'Library', 'Caches', 'dev.abar.native-overlay'),
      path.join(home, 'Library', 'Preferences', 'dev.abar.native-overlay.plist')
    ],
    hooksPath: path.join(codexHome, 'hooks.json')
  };
}

