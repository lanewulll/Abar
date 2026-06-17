#!/usr/bin/env node

import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reporterPath = path.join(__dirname, 'reporter.js');
const port = Number(process.env.ABAR_SERVER_PORT || 3987);
const command = `ABAR_SERVER_PORT=${port} node '${reporterPath.replace(/'/g, "'\\''")}'`;

const hook = {
  hooks: {
    SessionStart: [{ matcher: 'startup|resume|clear|compact', hooks: [{ type: 'command', command, timeout: 2 }] }],
    PreToolUse: [{ matcher: '*', hooks: [{ type: 'command', command, timeout: 2 }] }],
    PostToolUse: [{ matcher: '*', hooks: [{ type: 'command', command, timeout: 2 }] }],
    UserPromptSubmit: [{ hooks: [{ type: 'command', command, timeout: 2 }] }],
    SubagentStart: [{ matcher: '*', hooks: [{ type: 'command', command, timeout: 2 }] }],
    SubagentStop: [{ matcher: '*', hooks: [{ type: 'command', command, timeout: 2 }] }],
    Stop: [{ hooks: [{ type: 'command', command, timeout: 2 }] }]
  }
};

process.stdout.write(`${JSON.stringify(hook, null, 2)}\n`);
