#!/usr/bin/env node

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { serverPort } from './runtime-config.js';

const port = serverPort();
const timeoutMs = Math.max(50, Number(process.env.ABAR_REPORTER_TIMEOUT_MS || 800));
const debugEnabled = process.env.ABAR_REPORTER_DEBUG === '1';

let stdin = '';
let settled = false;

const hardStop = setTimeout(() => finish(), timeoutMs + 100);

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  stdin += chunk;
  if (stdin.length > 1024 * 1024) {
    stdin = stdin.slice(0, 1024 * 1024);
  }
});
process.stdin.on('end', () => {
  void postEvent(stdin);
});
process.stdin.on('error', (error) => {
  debugLog('stdin_error', error.message);
  finish();
});

async function postEvent(raw) {
  let payload;
  try {
    payload = JSON.parse(raw || '{}');
  } catch (error) {
    debugLog('invalid_json', error.message);
    finish();
    return;
  }

  payload = {
    ...payload,
    abar_connection: detectConnection(process.env)
  };

  const body = JSON.stringify(payload);
  const request = http.request(
    {
      hostname: '127.0.0.1',
      port,
      path: '/events',
      method: 'POST',
      timeout: timeoutMs,
      headers: {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body)
      }
    },
    (response) => {
      response.resume();
      response.on('end', () => finish());
    }
  );

  request.on('timeout', () => {
    request.destroy(new Error('timeout'));
  });
  request.on('error', (error) => {
    debugLog('post_error', error.message);
    finish();
  });
  request.end(body);
}

function detectConnection(env) {
  const baseUrl = firstNonEmpty(
    env.OPENAI_BASE_URL,
    env.OPENAI_API_BASE,
    env.OPENAI_BASEURL,
    env.CODEX_BASE_URL
  );
  const hasApiKey = Boolean(firstNonEmpty(env.OPENAI_API_KEY, env.CODEX_API_KEY));
  if (hasApiKey || baseUrl) {
    return {
      mode: 'api',
      ...(baseUrl ? { baseUrl } : { baseUrl: 'https://api.openai.com/v1' }),
      hasApiKey
    };
  }
  return {
    mode: 'account',
    hasApiKey: false
  };
}

function firstNonEmpty(...values) {
  return values.find((value) => typeof value === 'string' && value.trim())?.trim();
}

function finish() {
  if (settled) {
    return;
  }
  settled = true;
  clearTimeout(hardStop);
  process.exit(0);
}

function debugLog(kind, message) {
  if (!debugEnabled) {
    return;
  }
  try {
    const dir = path.join(os.homedir(), 'Library', 'Logs', 'Abar');
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(
      path.join(dir, 'codex-hook-reporter.log'),
      `${new Date().toISOString()} ${kind} ${String(message).slice(0, 300)}\n`
    );
  } catch {
    // Keep Codex hooks non-blocking even if local logging fails.
  }
}
