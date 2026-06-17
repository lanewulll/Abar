import { Menu, Tray, app, nativeImage } from 'electron';
import type { AbarDatabase } from '../backend/db/db';
import type { LocalServerStatus } from '../backend/types';
import { deriveActivityStatus } from '../backend/codex/activityAnalyzer';
import { resolveTrayIconPath } from './trayAssets';
import { formatTrayTitle } from './trayTitle';

type TrayActions = {
  openDashboard: () => void;
  openSettings: () => void;
  refreshQuota: () => Promise<void>;
  rescanSkills: () => Promise<void>;
};

let tray: Tray | null = null;

export function createAbarTray(db: AbarDatabase, getServerStatus: () => LocalServerStatus, actions: TrayActions): Tray {
  console.log('[Abar] creating tray');
  tray = new Tray(createTrayImage());
  console.log('[Abar] tray created');
  tray.setToolTip('Abar Codex Monitor');
  tray.on('click', actions.openDashboard);
  updateTray(db, getServerStatus, actions);
  console.log('[Abar] tray context menu attached');
  return tray;
}

export function updateTray(
  db: AbarDatabase,
  getServerStatus: () => LocalServerStatus,
  actions: TrayActions
): void {
  if (!tray) {
    return;
  }

  const quota = db.getLatestQuotaSnapshot();
  const events = db.listRecentEvents(1);
  const status = deriveActivityStatus(events);
  const projectPath = db.getProjectPath();
  const fiveHour = quota?.windows.find((window) => window.name === '5h');
  const weekly = quota?.windows.find((window) => window.name === 'weekly');
  const credits = quota?.credits?.remaining;
  const serverStatus = getServerStatus();
  tray.setTitle(formatTrayTitle(fiveHour?.usedPercent));
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Codex Monitor', enabled: false },
      { type: 'separator' },
      { label: `Status: ${status}`, enabled: false },
      { label: `5h: ${formatPercent(fiveHour?.usedPercent)}`, enabled: false },
      { label: `Weekly: ${formatPercent(weekly?.usedPercent)}`, enabled: false },
      { label: `Credits: ${credits ?? 'Not available'}`, enabled: false },
      { label: `Project: ${projectPath ? compactPath(projectPath) : 'Not configured'}`, enabled: false },
      {
        label: `Last Event: ${events[0] ? formatLastEvent(events[0]) : 'None'}`,
        enabled: false
      },
      {
        label: serverStatus.listening
          ? `Server: ${serverStatus.host}:${serverStatus.port}`
          : `Server: ${serverStatus.error ?? 'Not listening'}`,
        enabled: false
      },
      { type: 'separator' },
      { label: 'Open Dashboard', click: actions.openDashboard },
      { label: 'Refresh Quota', click: () => void actions.refreshQuota() },
      { label: 'Rescan Skills', click: () => void actions.rescanSkills() },
      { label: 'Settings', click: actions.openSettings },
      { type: 'separator' },
      { label: 'Quit', click: () => app.quit() }
    ])
  );
}

function createTrayImage(): Electron.NativeImage {
  const iconPath = resolveTrayIconPath({
    isPackaged: app.isPackaged,
    appPath: app.getAppPath(),
    resourcesPath: process.resourcesPath
  });
  const image = nativeImage.createFromPath(iconPath);
  console.log('[Abar] tray icon path:', iconPath);
  console.log('[Abar] tray image empty:', image.isEmpty());
  console.log('[Abar] tray image size:', image.getSize());
  if (image.isEmpty()) {
    console.warn('[Abar] tray icon failed to load; falling back to empty image with visible title');
    return nativeImage.createEmpty();
  }
  image.setTemplateImage(true);
  return image;
}

function formatPercent(value: number | undefined): string {
  return typeof value === 'number' ? `${Math.round(value)}% used` : 'Not available';
}

function compactPath(value: string): string {
  const parts = value.split('/');
  return parts.length > 2 ? `.../${parts.slice(-2).join('/')}` : value;
}

function formatLastEvent(event: { eventType: string; toolName?: string; createdAt: string }): string {
  const time = new Date(event.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  return `${event.toolName ?? event.eventType} ${time}`;
}
