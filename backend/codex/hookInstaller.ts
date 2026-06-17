export type HookInstallSnippet = {
  targetFile: string;
  hooksJson: string;
  configToml: string;
  reporterCommand: string;
  instructions: string[];
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

function buildReporterCommand(reporterPath: string, port: number, eventSecret?: string): string {
  const env = [`ABAR_SERVER_PORT=${port}`];
  if (eventSecret) {
    env.push(`ABAR_EVENT_SECRET=${quoteShell(eventSecret)}`);
  }
  return `${env.join(' ')} node ${quoteShell(reporterPath)}`;
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
