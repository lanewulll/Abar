import { BrowserWindow, screen, shell, Tray } from 'electron';
import type { Point, Rectangle } from 'electron';
import { is } from '@electron-toolkit/utils';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { calculatePopoverPlacement } from './popoverGeometry';
import { recoverRightEdgeStatusBounds } from './statusItemBounds';

const __dirname = dirname(fileURLToPath(import.meta.url));
const POPOVER_SIZE = {
  width: 420,
  height: 560
};

let popoverWindow: BrowserWindow | null = null;
let ignoreBlurUntil = 0;
let lastArrowOffsetX = Math.round(POPOVER_SIZE.width / 2);

export function togglePopover(tray: Tray, bounds?: Rectangle, position?: Point): void {
  if (popoverWindow?.isVisible()) {
    hidePopover();
    return;
  }
  showPopover(tray, bounds, position);
}

export function showPopover(tray: Tray, bounds?: Rectangle, position?: Point): BrowserWindow {
  const window = createPopoverWindow();
  if (!positionPopover(window, tray, bounds, position)) {
    console.warn('[Abar] popover not shown because no valid menu bar icon anchor was available');
    return window;
  }
  ignoreBlurUntil = Date.now() + 350;
  window.show();
  window.focus();
  return window;
}

export function hidePopover(): void {
  popoverWindow?.hide();
}

export function getPopoverWindow(): BrowserWindow | null {
  return popoverWindow;
}

function createPopoverWindow(): BrowserWindow {
  if (popoverWindow && !popoverWindow.isDestroyed()) {
    return popoverWindow;
  }

  popoverWindow = new BrowserWindow({
    width: POPOVER_SIZE.width,
    height: POPOVER_SIZE.height,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    title: 'Abar',
    backgroundColor: '#eef0ed',
    hasShadow: true,
    vibrancy: 'popover',
    visualEffectState: 'active',
    webPreferences: {
      preload: join(__dirname, '../preload/preload.mjs'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  popoverWindow.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: 'deny' };
  });

  popoverWindow.webContents.on('before-input-event', (event, input) => {
    if (input.key === 'Escape') {
      event.preventDefault();
      hidePopover();
    }
  });

  popoverWindow.on('blur', () => {
    if (Date.now() < ignoreBlurUntil) {
      return;
    }
    hidePopover();
  });

  popoverWindow.on('closed', () => {
    popoverWindow = null;
  });

  if (is.dev && process.env.ELECTRON_RENDERER_URL) {
    void popoverWindow.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void popoverWindow.loadFile(join(__dirname, '../../dist/index.html'));
  }

  return popoverWindow;
}

function positionPopover(window: BrowserWindow, tray: Tray, clickBounds?: Rectangle, clickPosition?: Point): boolean {
  const placement = resolvePlacement(tray, clickBounds, clickPosition);
  if (!placement) {
    return false;
  }
  lastArrowOffsetX = placement.arrowOffsetX;
  window.setBounds(placement.bounds);
  syncArrowOffset(window);
  return true;
}

function resolvePlacement(
  tray: Tray,
  clickBounds?: Rectangle,
  clickPosition?: Point
): ReturnType<typeof calculatePopoverPlacement> {
  const candidates = [
    clickBounds,
    tray.getBounds(),
    pointToTrayBounds(clickPosition),
    pointToTrayBounds(screen.getCursorScreenPoint())
  ].filter((bounds): bounds is Rectangle => Boolean(bounds));

  for (const trayBounds of candidates) {
    const display = screen.getDisplayNearestPoint({
      x: Math.round(trayBounds.x + trayBounds.width / 2),
      y: Math.round(trayBounds.y + trayBounds.height / 2)
    });
    const trayBoundsCandidates = [trayBounds, recoverRightEdgeStatusBounds(trayBounds, display.workArea)].filter(
      (bounds): bounds is Rectangle => Boolean(bounds)
    );
    for (const candidate of trayBoundsCandidates) {
      const placement = calculatePopoverPlacement({
        trayBounds: candidate,
        windowSize: POPOVER_SIZE,
        workArea: display.workArea,
        gap: 8,
        margin: 12
      });
      if (placement) {
        return placement;
      }
    }
  }

  return null;
}

function pointToTrayBounds(position?: Point): Rectangle | null {
  if (!position || !Number.isFinite(position.x) || !Number.isFinite(position.y)) {
    return null;
  }

  const display = screen.getDisplayNearestPoint(position);
  const nearMenuBar = position.y <= display.workArea.y + 12;
  if (!nearMenuBar) {
    return null;
  }

  return {
    x: Math.round(position.x - 12),
    y: Math.round(Math.max(0, position.y - 11)),
    width: 24,
    height: 22
  };
}

function syncArrowOffset(window: BrowserWindow): void {
  const script = `document.documentElement.style.setProperty('--popover-arrow-x', '${lastArrowOffsetX}px')`;
  if (window.webContents.isLoading()) {
    window.webContents.once('did-finish-load', () => {
      void window.webContents.executeJavaScript(script).catch(() => undefined);
    });
    return;
  }
  void window.webContents.executeJavaScript(script).catch(() => undefined);
}
