import { join } from 'node:path';

export const TRAY_ICON_FILENAME = 'trayTemplate.png';

export type TrayIconPathOptions = {
  isPackaged: boolean;
  appPath: string;
  resourcesPath: string;
};

export function resolveTrayIconPath(options: TrayIconPathOptions): string {
  if (options.isPackaged) {
    return join(options.resourcesPath, TRAY_ICON_FILENAME);
  }

  return join(options.appPath, 'electron', 'assets', TRAY_ICON_FILENAME);
}
