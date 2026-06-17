import { app, BrowserWindow } from 'electron';
import { optimizer } from '@electron-toolkit/utils';
import { join } from 'node:path';
import { AbarDatabase } from '../backend/db/db';
import { LocalEventServer } from '../backend/localServer';
import { scanSkills } from '../backend/codex/skillScanner';
import { refreshQuotaSnapshot } from '../backend/codex/quotaProvider';
import { createAbarTray, updateTray } from './tray';
import { createMainWindow, showMainWindow } from './window';
import { registerIpcHandlers } from './ipc';

let db: AbarDatabase;
let server: LocalEventServer;
let refreshTimer: NodeJS.Timeout | undefined;

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on('second-instance', () => {
  showMainWindow();
});

app.whenReady().then(async () => {
  app.setName('Abar');
  console.log('[Abar] app ready');

  db = new AbarDatabase(join(app.getPath('userData'), 'abar.sqlite'));
  ensureDefaultConfig(db);

  const reporterPath = getReporterPath();
  const serverPort = Number(db.getConfig('local_server_port') ?? 3987);
  server = new LocalEventServer({
    db,
    port: serverPort,
    eventSecret: db.getConfig('event_secret'),
    onEvent: () => refreshTray()
  });
  await server.start();

  const trayActions = {
    openDashboard: () => showMainWindow(),
    openSettings: () => showMainWindow('Settings'),
    refreshQuota: async () => {
      const snapshot = await refreshQuotaSnapshot();
      db.insertQuotaSnapshot(snapshot);
      refreshTray();
    },
    rescanSkills: async () => {
      const result = await scanSkills({
        projectPath: db.getProjectPath(),
        userHomePath: app.getPath('home')
      });
      db.replaceSkills(result.skills);
      refreshTray();
    }
  };

  try {
    createAbarTray(db, () => server.getStatus(), trayActions);
    console.log('[Abar] tray setup complete');
  } catch (error) {
    console.error('[Abar] failed to create tray:', error);
  }

  registerIpcHandlers({
    db,
    server,
    reporterPath,
    onDataChanged: () => refreshTray()
  });

  refreshTimer = setInterval(refreshTray, 30_000);

  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window);
  });
});

app.on('before-quit', () => {
  if (refreshTimer) {
    clearInterval(refreshTimer);
  }
  void server?.stop();
  db?.close();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createMainWindow();
  } else {
    showMainWindow();
  }
});

function ensureDefaultConfig(database: AbarDatabase): void {
  if (!database.getConfig('local_server_port')) {
    database.setConfig('local_server_port', '3987');
  }
}

function refreshTray(): void {
  if (!db || !server) {
    return;
  }
  updateTray(db, () => server.getStatus(), {
    openDashboard: () => showMainWindow(),
    openSettings: () => showMainWindow('Settings'),
    refreshQuota: async () => {
      const snapshot = await refreshQuotaSnapshot();
      db.insertQuotaSnapshot(snapshot);
      refreshTray();
    },
    rescanSkills: async () => {
      const result = await scanSkills({
        projectPath: db.getProjectPath(),
        userHomePath: app.getPath('home')
      });
      db.replaceSkills(result.skills);
      refreshTray();
    }
  });
}

function getReporterPath(): string {
  if (app.isPackaged) {
    return join(
      process.resourcesPath,
      'app.asar.unpacked',
      'reporters',
      'codex-hook-reporter',
      'reporter.js'
    );
  }

  return join(app.getAppPath(), 'reporters', 'codex-hook-reporter', 'reporter.js');
}
