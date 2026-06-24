#!/usr/bin/env node

import os from 'node:os';
import path from 'node:path';
import { serverPort } from './runtime-config.js';
import { buildAbarHookConfig } from '../../scripts/lib/hook-config.js';

const installDir = process.env.ABAR_INSTALL_DIR || path.join(os.homedir(), 'Applications');
const reporterPath = path.join(
  installDir,
  'Abar.app',
  'Contents',
  'Resources',
  'reporter',
  'reporter.js'
);
const port = serverPort();
const hook = buildAbarHookConfig(reporterPath, port);

process.stdout.write(`${JSON.stringify(hook, null, 2)}\n`);
