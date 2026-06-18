export type SkillSource = 'project' | 'user' | 'system' | 'unknown';

export type SkillInfo = {
  id: string;
  name: string;
  description: string;
  path: string;
  source: SkillSource;
  skillMdPath: string;
  hasSkillMd: boolean;
  lastModifiedAt?: string;
  error?: string;
};

export type SkillScanResult = {
  skills: SkillInfo[];
  errors: string[];
  scannedAt: string;
};

export type QuotaSnapshot = {
  provider: 'codex';
  source:
    | 'internal_web_api'
    | 'codex_auth_state'
    | 'local_estimate'
    | 'external_cli'
    | 'codex_oauth'
    | 'headers'
    | 'manual'
    | 'unknown';
  confidence: 'high' | 'medium' | 'low';
  windows: UsageWindow[];
  credits?: {
    remaining?: number;
    total?: number;
    unit?: string;
  };
  updatedAt: string;
  raw?: unknown;
  error?: string;
};

export type UsageWindow = {
  name: '5h' | 'weekly' | 'credits' | 'unknown';
  label?: string;
  sourceId?: string;
  usedPercent?: number;
  remainingPercent?: number;
  used?: number;
  limit?: number;
  unit?: 'messages' | 'tokens' | 'credits' | 'unknown';
  resetsAt?: string;
  resetInSeconds?: number;
};

export type CodexEventType =
  | 'SessionStart'
  | 'SessionEnd'
  | 'PreToolUse'
  | 'PostToolUse'
  | 'UserPromptSubmit'
  | 'Stop'
  | 'SubagentStart'
  | 'SubagentStop'
  | 'Unknown';

export type CodexEvent = {
  id: string;
  agent: 'codex';
  eventType: CodexEventType;
  projectPath?: string;
  sessionId?: string;
  toolName?: string;
  toolUseId?: string;
  status?: 'success' | 'error' | 'unknown';
  payload?: unknown;
  createdAt: string;
};

export type AgentRun = {
  sessionId: string;
  projectPath?: string;
  startedAt?: string;
  stoppedAt?: string;
  source?: string;
  status: 'running' | 'stopped' | 'unknown';
  durationSeconds?: number;
  lastEventAt: string;
};

export type AppConfig = {
  projectPath?: string;
  localServerPort: number;
  eventSecret?: string;
};

export type ActivityStatus = 'Active' | 'Idle' | 'Inactive' | 'Not configured';

export type LocalServerStatus = {
  listening: boolean;
  host: string;
  port: number;
  error?: string;
};
