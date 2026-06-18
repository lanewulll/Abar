#!/usr/bin/env electron
import { app, BrowserWindow, Tray, nativeImage, screen } from 'electron';
import { join } from 'node:path';

let tray;
let popover;

app.whenReady().then(() => {
  app.setName('Abar Smoke');

  const iconPath = join(process.cwd(), 'electron', 'assets', 'trayTemplate.png');
  const image = nativeImage.createFromPath(iconPath);
  console.log('[Abar Smoke] tray icon path:', iconPath);
  console.log('[Abar Smoke] tray image empty:', image.isEmpty());
  console.log('[Abar Smoke] tray image size:', image.getSize());

  const trayImage = image.isEmpty() ? nativeImage.createEmpty() : image;
  if (!trayImage.isEmpty()) {
    trayImage.setTemplateImage(true);
  }

  tray = new Tray(trayImage);
  tray.setTitle('Abar Smoke');
  tray.setToolTip('Abar smoke popover test');
  tray.on('click', togglePopover);
  console.log('[Abar Smoke] tray created; click "Abar Smoke" in the menu bar');
});

function togglePopover() {
  if (popover?.isVisible()) {
    popover.hide();
    return;
  }

  if (!popover || popover.isDestroyed()) {
    popover = new BrowserWindow({
      width: 260,
      height: 140,
      frame: false,
      resizable: false,
      show: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      backgroundColor: '#f6f7f4'
    });
    popover.loadURL(
      `data:text/html,${encodeURIComponent('<body style="font:14px -apple-system;padding:18px"><b>Abar Smoke</b><p>Popover opened from the menu bar.</p></body>')}`
    );
    popover.on('blur', () => popover?.hide());
  }

  const trayBounds = tray.getBounds();
  const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y });
  popover.setBounds({
    x: Math.max(display.workArea.x + 12, Math.round(trayBounds.x - 130)),
    y: display.workArea.y + 8,
    width: 260,
    height: 140
  });
  popover.show();
  popover.focus();
}

app.on('window-all-closed', (event) => {
  event.preventDefault();
});
