import type { Rectangle } from 'electron';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { AbarDatabase } from '../backend/db/db';

const electronMocks = vi.hoisted(() => {
  type Handler = (event: unknown, bounds: Rectangle, position?: Electron.Point) => void;

  const trayInstances: MockTray[] = [];

  class MockTray {
    handlers = new Map<string, Handler>();
    popUpContextMenu = vi.fn();
    setContextMenu = vi.fn();
    setTitle = vi.fn();
    setToolTip = vi.fn();

    constructor() {
      trayInstances.push(this);
    }

    on(eventName: string, listener: Handler): this {
      this.handlers.set(eventName, listener);
      return this;
    }
  }

  const menu = { id: 'tray-menu' };
  let lastTemplate: Electron.MenuItemConstructorOptions[] = [];

  return {
    app: {
      getAppPath: vi.fn(() => '/Users/lane/Desktop/codex/Abar'),
      isPackaged: false,
      quit: vi.fn()
    },
    menu,
    Menu: {
      buildFromTemplate: vi.fn((template: Electron.MenuItemConstructorOptions[]) => {
        lastTemplate = template;
        return menu;
      })
    },
    nativeImage: {
      createEmpty: vi.fn(() => ({
        isEmpty: () => true,
        getSize: () => ({ width: 0, height: 0 }),
        setTemplateImage: vi.fn()
      })),
      createFromPath: vi.fn(() => ({
        isEmpty: () => false,
        getSize: () => ({ width: 16, height: 16 }),
        setTemplateImage: vi.fn()
      }))
    },
    reset: () => {
      trayInstances.length = 0;
      electronMocks.Menu.buildFromTemplate.mockClear();
      electronMocks.nativeImage.createEmpty.mockClear();
      electronMocks.nativeImage.createFromPath.mockClear();
      electronMocks.app.getAppPath.mockClear();
      electronMocks.app.quit.mockClear();
      lastTemplate = [];
    },
    getLastTemplate: () => lastTemplate,
    Tray: MockTray,
    trayInstances
  };
});

vi.mock('electron', () => ({
  app: electronMocks.app,
  Menu: electronMocks.Menu,
  nativeImage: electronMocks.nativeImage,
  Tray: electronMocks.Tray
}));

function createDatabase(): AbarDatabase {
  return {
    getLatestQuotaSnapshot: () => undefined,
    getProjectPath: () => '/Users/lane/Desktop/codex/Abar',
    listRecentEvents: () => []
  } as unknown as AbarDatabase;
}

describe('createAbarTray', () => {
  beforeEach(() => {
    vi.resetModules();
    electronMocks.reset();
  });

  it('shows the quit menu only from right-click while left-click opens the popover', async () => {
    const { createAbarTray } = await import('../electron/tray');
    const togglePopover = vi.fn();
    const bounds: Rectangle = { x: 10, y: 20, width: 24, height: 24 };
    const position: Electron.Point = { x: 18, y: 28 };

    createAbarTray(createDatabase(), () => ({ listening: true, host: '127.0.0.1', port: 3987 }), {
      togglePopover,
      showSettings: vi.fn()
    });

    const tray = electronMocks.trayInstances[0];

    expect(tray.setContextMenu).not.toHaveBeenCalled();
    expect(tray.handlers.has('click')).toBe(true);
    expect(tray.handlers.has('right-click')).toBe(true);

    tray.handlers.get('click')?.({}, bounds, position);

    expect(togglePopover).toHaveBeenCalledTimes(1);
    expect(tray.popUpContextMenu).not.toHaveBeenCalled();

    tray.handlers.get('right-click')?.({}, bounds, position);

    expect(togglePopover).toHaveBeenCalledTimes(1);
    expect(tray.popUpContextMenu).toHaveBeenCalledWith(electronMocks.menu);
  });

  it('adds Settings to the right-click menu before Quit', async () => {
    const { createAbarTray } = await import('../electron/tray');
    const showSettings = vi.fn();

    createAbarTray(createDatabase(), () => ({ listening: true, host: '127.0.0.1', port: 3987 }), {
      togglePopover: vi.fn(),
      showSettings
    });

    const template = electronMocks.getLastTemplate();

    expect(template.map((item) => item.label)).toEqual(['Settings', 'Quit Abar']);
    template[0].click?.({} as Electron.MenuItem, undefined, {} as Electron.KeyboardEvent);
    template[1].click?.({} as Electron.MenuItem, undefined, {} as Electron.KeyboardEvent);

    expect(showSettings).toHaveBeenCalledTimes(1);
    expect(electronMocks.app.quit).toHaveBeenCalledTimes(1);
  });
});
