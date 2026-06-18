import type {
  AgentRun,
  CodexEvent,
  LocalServerStatus,
  QuotaSnapshot,
  SkillInfo
} from '../../backend/types';
import type { HookInstallPrompt, HookInstallSnippet } from '../../backend/codex/hookInstaller';

export type AppState = {
  config: {
    projectPath?: string;
    localServerPort: number;
  };
  server: LocalServerStatus;
  quota?: QuotaSnapshot;
  skills: SkillInfo[];
  events: CodexEvent[];
  agentRuns: AgentRun[];
};

export type Notice = {
  tone: 'info' | 'success' | 'error';
  message: string;
};

export type { AgentRun, CodexEvent, HookInstallPrompt, HookInstallSnippet, QuotaSnapshot, SkillInfo };
