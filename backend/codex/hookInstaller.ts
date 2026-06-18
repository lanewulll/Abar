import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

export type HookInstallSnippet = {
  targetFile: string;
  hooksJson: string;
  configToml: string;
  reporterCommand: string;
  instructions: string[];
};

export type HookInstallPrompt = {
  targetFile: string;
  promptText: string;
  reporterCommand: string;
};

export type HookInstallStatus = 'installed' | 'updated' | 'unchanged';

export type HookInstallResult = {
  status: HookInstallStatus;
  targetFile: string;
  backupFile?: string;
  reporterCommand: string;
};

type HookCommand = {
  type: 'command';
  command: string;
  timeout: number;
};

type HookEntry = {
  matcher?: string;
  hooks: HookCommand[];
};

type HooksJson = {
  hooks?: Record<string, HookEntry[]>;
};

const ABAR_REPORTER_MARKER = 'codex-hook-reporter/reporter.js';
const HOOK_EVENT_CONFIG: Record<string, { matcher?: string }> = {
  SessionStart: { matcher: 'startup|resume|clear|compact' },
  PreToolUse: { matcher: '*' },
  PostToolUse: { matcher: '*' },
  UserPromptSubmit: {},
  SubagentStart: { matcher: '*' },
  SubagentStop: { matcher: '*' },
  Stop: {}
};

export function generateHookInstallSnippet(options: {
  reporterPath: string;
  port: number;
  eventSecret?: string;
  homePath: string;
}): HookInstallSnippet {
  const reporterCommand = buildReporterCommand(options.reporterPath, options.port, options.eventSecret);
  const commandHook = {
    type: 'command',
    command: reporterCommand,
    timeout: 2
  };

  const hooksJsonObject = {
    hooks: {
      SessionStart: [{ matcher: 'startup|resume|clear|compact', hooks: [commandHook] }],
      PreToolUse: [{ matcher: '*', hooks: [commandHook] }],
      PostToolUse: [{ matcher: '*', hooks: [commandHook] }],
      UserPromptSubmit: [{ hooks: [commandHook] }],
      SubagentStart: [{ matcher: '*', hooks: [commandHook] }],
      SubagentStop: [{ matcher: '*', hooks: [commandHook] }],
      Stop: [{ hooks: [commandHook] }]
    }
  };

  return {
    targetFile: `${options.homePath}/.codex/hooks.json`,
    hooksJson: `${JSON.stringify(hooksJsonObject, null, 2)}\n`,
    configToml: buildTomlSnippet(reporterCommand),
    reporterCommand,
    instructions: [
      'Copy the hooks.json snippet into ~/.codex/hooks.json, or merge it with existing hooks.',
      'Restart Codex or open /hooks in the Codex CLI.',
      'Review and trust the Abar hook definitions before expecting events to appear.',
      'Abar only receives events while the app is running and the local server is listening.'
    ]
  };
}

export function generateHookInstallPrompt(options: {
  reporterPath: string;
  port: number;
  eventSecret?: string;
  homePath: string;
}): HookInstallPrompt {
  const snippet = generateHookInstallSnippet(options);
  const promptText = [
    '请帮我安装 Abar 的 Codex hooks；安装后不需要尝试替我完成 trust。',
    '',
    `目标文件：${snippet.targetFile}`,
    '',
    '要求：',
    '1. 如果目标文件不存在，请创建它；如果已经存在，请先备份，再保留现有 hooks 并合并下面这份 Abar hooks。',
    '2. 如果已有旧的 Abar hook 命令包含 codex-hook-reporter/reporter.js，请更新它，不要重复追加；也就是要去重。',
    '3. 安装完成后，请直接告诉我：你不能替我完成 trust，我需要亲自在 /hooks 里 review 并 trust 这些 Abar hooks，否则事件不会被 Codex 执行。',
    '',
    '需要合并的 hooks.json 内容：',
    '```json',
    snippet.hooksJson.trimEnd(),
    '```'
  ].join('\n');

  return {
    targetFile: snippet.targetFile,
    promptText,
    reporterCommand: snippet.reporterCommand
  };
}

export function installCodexHooks(options: {
  reporterPath: string;
  port: number;
  eventSecret?: string;
  homePath: string;
}): HookInstallResult {
  const snippet = generateHookInstallSnippet(options);
  const targetFile = snippet.targetFile;
  const existingText = existsSync(targetFile) ? readFileSync(targetFile, 'utf8') : undefined;
  const existing = parseHooksJson(existingText);
  const next = mergeAbarHooks(existing, snippet.reporterCommand);
  const nextText = `${JSON.stringify(next.value, null, 2)}\n`;

  if (existingText === nextText) {
    return {
      status: 'unchanged',
      targetFile,
      reporterCommand: snippet.reporterCommand
    };
  }

  mkdirSync(dirname(targetFile), { recursive: true });
  let backupFile: string | undefined;
  if (existingText !== undefined) {
    backupFile = `${targetFile}.abar-backup`;
    if (!existsSync(backupFile)) {
      copyFileSync(targetFile, backupFile);
    }
  }
  writeFileSync(targetFile, nextText);

  return {
    status: next.replacedExistingAbarHook ? 'updated' : 'installed',
    targetFile,
    backupFile,
    reporterCommand: snippet.reporterCommand
  };
}

function buildReporterCommand(reporterPath: string, port: number, eventSecret?: string): string {
  const env = [`ABAR_SERVER_PORT=${port}`];
  if (eventSecret) {
    env.push(`ABAR_EVENT_SECRET=${quoteShell(eventSecret)}`);
  }
  return `${env.join(' ')} node ${quoteShell(reporterPath)}`;
}

function parseHooksJson(value: string | undefined): HooksJson {
  if (!value?.trim()) {
    return {};
  }
  const parsed = JSON.parse(value) as unknown;
  return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed) ? (parsed as HooksJson) : {};
}

function mergeAbarHooks(existing: HooksJson, reporterCommand: string): { value: HooksJson; replacedExistingAbarHook: boolean } {
  const merged: HooksJson = {
    ...existing,
    hooks: {
      ...(existing.hooks ?? {})
    }
  };
  let replacedExistingAbarHook = false;

  for (const [eventName, eventConfig] of Object.entries(HOOK_EVENT_CONFIG)) {
    const entries = Array.isArray(merged.hooks?.[eventName]) ? [...(merged.hooks?.[eventName] ?? [])] : [];
    const withoutAbar = entries.filter((entry) => {
      const hasAbarHook = Array.isArray(entry.hooks)
        ? entry.hooks.some((hook) => hook.type === 'command' && hook.command.includes(ABAR_REPORTER_MARKER))
        : false;
      if (hasAbarHook) {
        replacedExistingAbarHook = true;
      }
      return !hasAbarHook;
    });

    merged.hooks![eventName] = [
      ...withoutAbar,
      {
        ...eventConfig,
        hooks: [
          {
            type: 'command',
            command: reporterCommand,
            timeout: 2
          }
        ]
      }
    ];
  }

  return { value: merged, replacedExistingAbarHook };
}

function buildTomlSnippet(command: string): string {
  return `[[hooks.SessionStart]]
matcher = "startup|resume|clear|compact"
[[hooks.SessionStart.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2

[[hooks.PreToolUse]]
matcher = "*"
[[hooks.PreToolUse.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2

[[hooks.PostToolUse]]
matcher = "*"
[[hooks.PostToolUse.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2

[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2

[[hooks.SubagentStart]]
matcher = "*"
[[hooks.SubagentStart.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2

[[hooks.SubagentStop]]
matcher = "*"
[[hooks.SubagentStop.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = ${JSON.stringify(command)}
timeout = 2
`;
}

function quoteShell(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}
