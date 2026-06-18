import { contextBridge, ipcRenderer } from 'electron';
import { APP_STATE_CHANGED_CHANNEL } from './appEvents';

const api = {
  getState: () => ipcRenderer.invoke('app:getState'),
  onStateChanged: (listener: () => void) => {
    const handler = () => listener();
    ipcRenderer.on(APP_STATE_CHANGED_CHANNEL, handler);
    return () => {
      ipcRenderer.off(APP_STATE_CHANGED_CHANNEL, handler);
    };
  },
  quit: () => ipcRenderer.invoke('app:quit'),
  config: {
    get: () => ipcRenderer.invoke('config:get'),
    setProjectPath: (projectPath: string) => ipcRenderer.invoke('config:setProjectPath', projectPath),
    chooseProjectPath: () => ipcRenderer.invoke('config:chooseProjectPath')
  },
  skills: {
    list: () => ipcRenderer.invoke('skills:list'),
    rescan: () => ipcRenderer.invoke('skills:rescan')
  },
  quota: {
    getLatest: () => ipcRenderer.invoke('quota:getLatest'),
    refresh: () => ipcRenderer.invoke('quota:refresh')
  },
  events: {
    list: (limit?: number) => ipcRenderer.invoke('events:list', limit),
    createTest: () => ipcRenderer.invoke('events:createTest')
  },
  hooks: {
    getInstallPrompt: () => ipcRenderer.invoke('hooks:getInstallPrompt'),
    copyInstallPrompt: () => ipcRenderer.invoke('hooks:copyInstallPrompt')
  },
  shell: {
    openPath: (targetPath: string) => ipcRenderer.invoke('shell:openPath', targetPath)
  }
};

contextBridge.exposeInMainWorld('abar', api);

export type AbarApi = typeof api;
