import { app, ipcMain, dialog, shell, clipboard } from 'electron';
import { homedir } from 'node:os';
import type { AbarDatabase } from '../backend/db/db';
import { scanSkills } from '../backend/codex/skillScanner';
import { refreshQuotaSnapshot } from '../backend/codex/quotaProvider';
import { normalizeCodexHookPayload } from '../backend/codex/activityAnalyzer';
import type { LocalEventServer } from '../backend/localServer';
import { generateHookInstallPrompt } from '../backend/codex/hookInstaller';

export type IpcOptions = {
  db: AbarDatabase;
  server: LocalEventServer;
  reporterPath: string;
  onDataChanged: () => void;
};

export function registerIpcHandlers(options: IpcOptions): void {
  ipcMain.handle('app:getState', () => ({
    config: {
      projectPath: options.db.getProjectPath(),
      localServerPort: Number(options.db.getConfig('local_server_port') ?? 3987)
    },
    server: options.server.getStatus(),
    quota: options.db.getLatestQuotaSnapshot(),
    skills: options.db.listSkills(),
    events: options.db.listRecentEvents(50),
    agentRuns: options.db.listRecentAgentRuns(5)
  }));

  ipcMain.handle('config:get', () => ({
    projectPath: options.db.getProjectPath(),
    localServerPort: Number(options.db.getConfig('local_server_port') ?? 3987)
  }));

  ipcMain.handle('config:setProjectPath', (_event, projectPath: string) => {
    options.db.setProjectPath(projectPath);
    options.onDataChanged();
    return { ok: true, projectPath };
  });

  ipcMain.handle('config:chooseProjectPath', async () => {
    const result = await dialog.showOpenDialog({
      title: 'Choose Codex project folder',
      properties: ['openDirectory', 'createDirectory']
    });
    if (result.canceled || !result.filePaths[0]) {
      return { ok: false };
    }
    options.db.setProjectPath(result.filePaths[0]);
    options.onDataChanged();
    return { ok: true, projectPath: result.filePaths[0] };
  });

  ipcMain.handle('skills:list', () => options.db.listSkills());

  ipcMain.handle('skills:rescan', async () => {
    const result = await scanSkills({
      projectPath: options.db.getProjectPath(),
      userHomePath: homedir()
    });
    options.db.replaceSkills(result.skills);
    options.onDataChanged();
    return result;
  });

  ipcMain.handle('quota:getLatest', () => options.db.getLatestQuotaSnapshot());

  ipcMain.handle('quota:refresh', async () => {
    const snapshot = await refreshQuotaSnapshot();
    options.db.insertQuotaSnapshot(snapshot);
    options.onDataChanged();
    return snapshot;
  });

  ipcMain.handle('events:list', (_event, limit = 50) => options.db.listRecentEvents(limit));

  ipcMain.handle('events:createTest', () => {
    const event = normalizeCodexHookPayload({
      hook_event_name: 'PreToolUse',
      session_id: 'abar-test-session',
      cwd: options.db.getProjectPath() ?? process.cwd(),
      tool_name: 'Bash',
      tool_use_id: 'abar-test-tool',
      tool_input: {
        command: 'echo abar-test'
      }
    });
    options.db.insertEvent(event);
    options.onDataChanged();
    return event;
  });

  ipcMain.handle('hooks:getInstallPrompt', () =>
    generateHookInstallPrompt({
      reporterPath: options.reporterPath,
      port: Number(options.db.getConfig('local_server_port') ?? 3987),
      eventSecret: options.db.getConfig('event_secret'),
      homePath: homedir()
    })
  );

  ipcMain.handle('hooks:copyInstallPrompt', () => {
    const prompt = generateHookInstallPrompt({
      reporterPath: options.reporterPath,
      port: Number(options.db.getConfig('local_server_port') ?? 3987),
      eventSecret: options.db.getConfig('event_secret'),
      homePath: homedir()
    });
    clipboard.writeText(prompt.promptText);
    return { ok: true };
  });

  ipcMain.handle('shell:openPath', async (_event, targetPath: string) => {
    const error = await shell.openPath(targetPath);
    return { ok: !error, error: error || undefined };
  });

  ipcMain.handle('app:quit', () => {
    app.quit();
    return { ok: true };
  });
}
