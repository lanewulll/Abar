import { Tray, app, nativeImage } from 'electron';
import type { Point, Rectangle } from 'electron';
import type { AbarDatabase } from '../backend/db/db';
import type { LocalServerStatus } from '../backend/types';
import { deriveActivityStatus } from '../backend/codex/activityAnalyzer';
import { resolveTrayIconPath } from './trayAssets';
import { formatTrayTitle } from './trayTitle';

type TrayActions = {
  togglePopover: (tray: Tray, bounds?: Rectangle, position?: Point) => void;
};

type TrayWithMouseUp = Tray & {
  on(event: 'mouse-up', listener: (event: unknown, bounds: Rectangle, position?: Point) => void): Tray;
};

let tray: Tray | null = null;
let lastTrayActivationAt = 0;

export function createAbarTray(db: AbarDatabase, getServerStatus: () => LocalServerStatus, actions: TrayActions): Tray {
  console.log('[Abar] creating tray');
  tray = new Tray(createTrayImage());
  console.log('[Abar] tray created');
  tray.setToolTip('Abar Codex Monitor');
  const activateTray = (bounds?: Rectangle, position?: Point) => {
    const now = Date.now();
    if (now - lastTrayActivationAt < 220) {
      return;
    }
    lastTrayActivationAt = now;
    actions.togglePopover(tray as Tray, bounds, position);
  };
  tray.on('click', (_event, bounds, position) => activateTray(bounds, position));
  (tray as TrayWithMouseUp).on('mouse-up', (_event: unknown, bounds: Rectangle, position?: Point) =>
    activateTray(bounds, position)
  );
  tray.on('right-click', (_event, bounds) => activateTray(bounds));
  updateTray(db, getServerStatus, actions);
  console.log('[Abar] tray click handler attached');
  return tray;
}

export function updateTray(
  db: AbarDatabase,
  getServerStatus: () => LocalServerStatus,
  _actions: TrayActions
): void {
  if (!tray) {
    return;
  }

  const quota = db.getLatestQuotaSnapshot();
  const events = db.listRecentEvents(1);
  const status = deriveActivityStatus(events);
  const projectPath = db.getProjectPath();
  const fiveHour = quota?.windows.find((window) => window.name === '5h');
  tray.setTitle(formatTrayTitle(fiveHour?.usedPercent));
  tray.setToolTip(
    `Abar Codex Monitor · ${status} · ${projectPath ? compactPath(projectPath) : 'No project'} · ${
      getServerStatus().listening ? 'Server online' : 'Server offline'
    }`
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
  image.setTemplateImage(false);
  return image;
}

function compactPath(value: string): string {
  const parts = value.split('/');
  return parts.length > 2 ? `.../${parts.slice(-2).join('/')}` : value;
}
