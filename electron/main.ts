import { app, BrowserWindow } from 'electron';
import { optimizer } from '@electron-toolkit/utils';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { AbarDatabase } from '../backend/db/db';
import { LocalEventServer } from '../backend/localServer';
import { refreshQuotaSnapshot } from '../backend/codex/quotaProvider';
import { scanSkills } from '../backend/codex/skillScanner';
import { createAbarTray, updateTray } from './tray';
import { registerIpcHandlers } from './ipc';
import { showSettingsPopover, togglePopover } from './popover';
import { AUTO_REFRESH_INTERVALS_MS } from './trayBehavior';
import { broadcastStateChanged } from './appEvents';

let db: AbarDatabase;
let server: LocalEventServer;
let refreshTimer: NodeJS.Timeout | undefined;
let quotaRefreshTimer: NodeJS.Timeout | undefined;
let skillsRefreshTimer: NodeJS.Timeout | undefined;
let quotaRefreshInFlight = false;
let skillsRefreshInFlight = false;

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on('second-instance', () => {
  refreshTray();
});

app.whenReady().then(async () => {
  app.setName('Abar');
  if (process.platform === 'darwin') {
    app.dock?.hide();
  }
  console.log('[Abar] app ready');

  db = new AbarDatabase(join(app.getPath('userData'), 'abar.sqlite'));
  ensureDefaultConfig(db);

  const reporterPath = getReporterPath();
  const serverPort = Number(db.getConfig('local_server_port') ?? 3987);

  server = new LocalEventServer({
    db,
    port: serverPort,
    eventSecret: db.getConfig('event_secret'),
    onEvent: () => handleDataChanged()
  });
  await server.start();

  const trayActions = {
    togglePopover,
    showSettings: showSettingsPopover
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
    onDataChanged: () => handleDataChanged()
  });
  void refreshMissingQuotaSnapshot();
  void refreshSkillsSnapshot();
  startAutoRefreshTimers();

  refreshTimer = setInterval(refreshTray, 30_000);

  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window);
  });
});

app.on('before-quit', () => {
  if (refreshTimer) {
    clearInterval(refreshTimer);
  }
  if (quotaRefreshTimer) {
    clearInterval(quotaRefreshTimer);
  }
  if (skillsRefreshTimer) {
    clearInterval(skillsRefreshTimer);
  }
  void server?.stop();
  db?.close();
});

app.on('activate', () => {
  refreshTray();
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
    togglePopover,
    showSettings: showSettingsPopover
  });
}

function handleDataChanged(): void {
  refreshTray();
  broadcastStateChanged(BrowserWindow.getAllWindows());
}

async function refreshMissingQuotaSnapshot(): Promise<void> {
  if (!db || db.getLatestQuotaSnapshot()) {
    return;
  }

  await refreshQuotaSnapshotAndTray();
}

function startAutoRefreshTimers(): void {
  quotaRefreshTimer = setInterval(
    () => void refreshQuotaSnapshotAndTray(),
    AUTO_REFRESH_INTERVALS_MS.quota
  );
  skillsRefreshTimer = setInterval(
    () => void refreshSkillsSnapshot(),
    AUTO_REFRESH_INTERVALS_MS.skills
  );
}

async function refreshQuotaSnapshotAndTray(): Promise<void> {
  if (!db || quotaRefreshInFlight) {
    return;
  }

  quotaRefreshInFlight = true;
  try {
    const snapshot = await refreshQuotaSnapshot();
    db.insertQuotaSnapshot(snapshot);
    handleDataChanged();
  } catch (error) {
    console.error('[Abar] failed to refresh quota:', error);
  } finally {
    quotaRefreshInFlight = false;
  }
}

async function refreshSkillsSnapshot(): Promise<void> {
  if (!db || skillsRefreshInFlight) {
    return;
  }

  skillsRefreshInFlight = true;
  try {
    const result = await scanSkills({
      projectPath: db.getProjectPath(),
      userHomePath: homedir()
    });
    db.replaceSkills(result.skills);
    handleDataChanged();
    if (result.errors.length > 0) {
      console.warn(`[Abar] skill scan completed with ${result.errors.length} warning(s)`);
    }
  } catch (error) {
    console.error('[Abar] failed to refresh skills:', error);
  } finally {
    skillsRefreshInFlight = false;
  }
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
