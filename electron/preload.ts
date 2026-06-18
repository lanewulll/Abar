import { contextBridge, ipcRenderer } from 'electron';

const api = {
  getState: () => ipcRenderer.invoke('app:getState'),
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
    getInstallSnippet: () => ipcRenderer.invoke('hooks:getInstallSnippet'),
    copyInstallSnippet: () => ipcRenderer.invoke('hooks:copyInstallSnippet')
  },
  shell: {
    openPath: (targetPath: string) => ipcRenderer.invoke('shell:openPath', targetPath)
  }
};

contextBridge.exposeInMainWorld('abar', api);

export type AbarApi = typeof api;
