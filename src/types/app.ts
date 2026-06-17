import type {
  CodexEvent,
  LocalServerStatus,
  QuotaSnapshot,
  SkillInfo
} from '../../backend/types';
import type { HookInstallSnippet } from '../../backend/codex/hookInstaller';

export type PageName = 'Overview' | 'Quota' | 'Skills' | 'Activity' | 'Settings';

export type AppState = {
  config: {
    projectPath?: string;
    localServerPort: number;
  };
  server: LocalServerStatus;
  quota?: QuotaSnapshot;
  skills: SkillInfo[];
  events: CodexEvent[];
};

export type Notice = {
  tone: 'info' | 'success' | 'error';
  message: string;
};

export type { CodexEvent, HookInstallSnippet, QuotaSnapshot, SkillInfo };
