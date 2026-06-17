import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { normalizeCodexHookPayload } from './codex/activityAnalyzer';
import type { LocalServerStatus } from './types';
import type { AbarDatabase } from './db/db';

export type LocalServerOptions = {
  db: AbarDatabase;
  host?: string;
  port: number;
  eventSecret?: string;
  onEvent?: () => void;
};

export class LocalEventServer {
  private server?: Server;
  private status: LocalServerStatus;

  constructor(private readonly options: LocalServerOptions) {
    this.status = {
      listening: false,
      host: options.host ?? '127.0.0.1',
      port: options.port
    };
  }

  start(): Promise<LocalServerStatus> {
    if (this.server) {
      return Promise.resolve(this.status);
    }

    this.server = createServer((request, response) => {
      void this.handleRequest(request, response);
    });

    this.server.on('error', (error) => {
      this.status = {
        listening: false,
        host: this.options.host ?? '127.0.0.1',
        port: this.options.port,
        error: error instanceof Error ? error.message : String(error)
      };
    });

    return new Promise((resolve) => {
      this.server?.listen(this.options.port, this.options.host ?? '127.0.0.1', () => {
        const address = this.server?.address() as AddressInfo;
        this.status = {
          listening: true,
          host: address.address,
          port: address.port
        };
        resolve(this.status);
      });

      this.server?.once('error', () => {
        resolve(this.status);
      });
    });
  }

  stop(): Promise<void> {
    return new Promise((resolve) => {
      if (!this.server) {
        resolve();
        return;
      }
      this.server.close(() => {
        this.server = undefined;
        this.status = {
          listening: false,
          host: this.options.host ?? '127.0.0.1',
          port: this.options.port
        };
        resolve();
      });
    });
  }

  getStatus(): LocalServerStatus {
    return this.status;
  }

  private async handleRequest(request: IncomingMessage, response: ServerResponse): Promise<void> {
    if (request.method === 'GET' && request.url === '/health') {
      sendJson(response, 200, {
        ok: this.status.listening,
        service: 'abar',
        status: this.status
      });
      return;
    }

    if (request.method === 'POST' && request.url === '/events') {
      if (this.options.eventSecret && request.headers['x-abar-secret'] !== this.options.eventSecret) {
        sendJson(response, 401, { ok: false, error: 'Unauthorized' });
        return;
      }

      try {
        const body = await readBody(request);
        const payload = JSON.parse(body);
        const event = normalizeCodexHookPayload(payload);
        this.options.db.insertEvent(event);
        this.options.onEvent?.();
        sendJson(response, 202, { ok: true, id: event.id });
      } catch (error) {
        sendJson(response, 400, {
          ok: false,
          error: error instanceof Error ? error.message : String(error)
        });
      }
      return;
    }

    sendJson(response, 404, { ok: false, error: 'Not found' });
  }
}

function readBody(request: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = '';
    request.setEncoding('utf8');
    request.on('data', (chunk: string) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        request.destroy();
        reject(new Error('Payload too large'));
      }
    });
    request.on('end', () => resolve(body));
    request.on('error', reject);
  });
}

function sendJson(response: ServerResponse, statusCode: number, body: unknown): void {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  response.end(JSON.stringify(body));
}
