import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import test from 'node:test';

test('reporter posts hook payload to the configured local port without a secret header', async () => {
  const received = await new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      let body = '';
      request.setEncoding('utf8');
      request.on('data', (chunk) => {
        body += chunk;
      });
      request.on('end', () => {
        response.writeHead(202);
        response.end();
        server.close();
        resolve({
          method: request.method,
          url: request.url,
          headers: request.headers,
          body: JSON.parse(body)
        });
      });
    });

    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const child = spawn(process.execPath, ['reporters/codex-hook-reporter/reporter.js'], {
        cwd: new URL('../..', import.meta.url),
        env: {
          ...process.env,
          ABAR_SERVER_PORT: String(address.port),
          ABAR_EVENT_SECRET: 'must-not-be-sent'
        },
        stdio: ['pipe', 'ignore', 'pipe']
      });
      child.stderr.on('data', (chunk) => reject(new Error(chunk.toString())));
      child.on('error', reject);
      child.stdin.end(JSON.stringify({ hook_event_name: 'Stop', cwd: '/tmp/project' }));
    });
  });

  assert.equal(received.method, 'POST');
  assert.equal(received.url, '/events');
  assert.equal(received.headers['x-abar-secret'], undefined);
  assert.equal(received.body.hook_event_name, 'Stop');
  assert.equal(received.body.abar_connection.mode, 'account');
});
