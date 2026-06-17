#!/usr/bin/env electron
import { app, Menu, Tray, nativeImage } from 'electron';
import { join } from 'node:path';

let tray;

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
  tray.setToolTip('Abar smoke tray test');
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Abar Smoke', enabled: false },
      { type: 'separator' },
      { label: 'Quit', click: () => app.quit() }
    ])
  );
  console.log('[Abar Smoke] tray created; look for "Abar Smoke" in the menu bar');
});

app.on('window-all-closed', (event) => {
  event.preventDefault();
});
