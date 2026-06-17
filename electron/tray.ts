import { Menu, Tray, app, nativeImage } from 'electron';
import type { AbarDatabase } from '../backend/db/db';
import type { LocalServerStatus } from '../backend/types';
import { deriveActivityStatus } from '../backend/codex/activityAnalyzer';
import { formatTrayTitle } from './trayTitle';

type TrayActions = {
  openDashboard: () => void;
  openSettings: () => void;
  refreshQuota: () => Promise<void>;
  rescanSkills: () => Promise<void>;
};

let tray: Tray | null = null;

export function createAbarTray(db: AbarDatabase, getServerStatus: () => LocalServerStatus, actions: TrayActions): Tray {
  tray = new Tray(createTrayImage());
  tray.setToolTip('Abar Codex Monitor');
  tray.on('click', actions.openDashboard);
  updateTray(db, getServerStatus, actions);
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
  const svg = encodeURIComponent(`
    <svg width="18" height="18" viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
      <path d="M11.85 5.55c-.62-.5-1.4-.75-2.33-.75-2.05 0-3.45 1.58-3.45 4.14 0 2.57 1.38 4.19 3.47 4.19.96 0 1.78-.28 2.45-.85l.74 1.12c-.84.73-1.94 1.1-3.3 1.1-2.97 0-4.98-2.18-4.98-5.56 0-3.34 2.05-5.5 5.02-5.5 1.32 0 2.4.34 3.24 1.03l-.86 1.08Z" fill="#000"/>
    </svg>
  `);
  const image = nativeImage.createFromDataURL(`data:image/svg+xml;charset=utf-8,${svg}`);
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
