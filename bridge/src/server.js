// Bridge server: accepts events from adapters over HTTP and streams them to clients over WebSocket.
//
//   POST /event              canonical event (or array of events)
//   POST /hook/claude-code   raw Claude Code hook payload
//   POST /hook/opencode      { event } as seen by an OpenCode plugin's event hook
//   POST /hook/pi            { session, event } with a Pi session event
//   POST /hook/hermes        raw Hermes shell-hook payload
//                            (raw payloads are mapped by the built-in adapters)
//   GET  /health             liveness and counters
//   WS   /ws                 clients receive canonical events as JSON text frames
//
// Binds to 127.0.0.1 by default: events can contain commands and file names.

import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { SCHEMA_VERSION, normalizeEvent, validateEvent } from './schema.js';
import { createClaudeCodeAdapter } from './adapters/claude-code.js';
import { createOpenCodeAdapter } from './adapters/opencode.js';
import { createPiAdapter } from './adapters/pi.js';
import { createHermesAdapter } from './adapters/hermes.js';

// Hook payloads can contain whole tool outputs (the bridge is local and only forwards a few fields),
// so the limit is generous: a rejected post would silently lose a tool_end.
const MAX_BODY_BYTES = 10_000_000;

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('payload too large'), { status: 413 }));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function sendJson(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text) });
  res.end(text);
}

export function createBridge({ host = '127.0.0.1', port = 8787, redactTargets = false, log = () => {} } = {}) {
  const claudeCode = createClaudeCodeAdapter();
  const openCode = createOpenCodeAdapter();
  const pi = createPiAdapter();
  const hermes = createHermesAdapter();
  // Raw payload -> canonical events, per framework id (the :framework part of /hook/:framework).
  const adapters = {
    'claude-code': (payload) => claudeCode.fromHook(payload),
    opencode: (payload) => openCode.fromPayload(payload),
    pi: (payload) => pi.fromPayload(payload),
    hermes: (payload) => hermes.fromHook(payload),
  };
  const stats = { events: 0, rejected: 0 };

  const server = http.createServer(async (req, res) => {
    try {
      const { pathname } = new URL(req.url ?? '/', 'http://localhost');

      if (req.method === 'GET' && pathname === '/health') {
        return sendJson(res, 200, { ok: true, schema: SCHEMA_VERSION, clients: wss.clients.size, ...stats });
      }

      if (req.method === 'POST' && pathname === '/event') {
        const body = JSON.parse(await readBody(req));
        const list = Array.isArray(body) ? body : [body];
        const accepted = [];
        const errors = [];
        list.forEach((raw, index) => {
          const event = normalizeEvent(raw, { redactTargets });
          const problems = validateEvent(event);
          if (problems.length === 0) accepted.push(event);
          else errors.push({ index, errors: problems });
        });
        accepted.forEach(broadcast);
        stats.rejected += errors.length;
        return sendJson(res, errors.length ? 400 : 202, { accepted: accepted.length, rejected: errors });
      }

      const hook = req.method === 'POST' ? /^\/hook\/([a-z-]+)$/.exec(pathname) : null;
      if (hook && adapters[hook[1]]) {
        const payload = JSON.parse(await readBody(req));
        for (const raw of adapters[hook[1]](payload)) {
          const event = normalizeEvent(raw, { redactTargets });
          const problems = validateEvent(event);
          if (problems.length === 0) broadcast(event);
          else {
            stats.rejected += 1;
            log(`dropped ${hook[1]} event: ${problems.join('; ')}`);
          }
        }
        res.writeHead(204);
        return res.end();
      }

      return sendJson(res, 404, { error: 'not found' });
    } catch (err) {
      const status = err.status ?? (err instanceof SyntaxError ? 400 : 500);
      return sendJson(res, status, { error: err.message });
    }
  });

  const wss = new WebSocketServer({ server, path: '/ws' });
  wss.on('connection', (socket) => {
    socket.send(JSON.stringify({ v: SCHEMA_VERSION, type: 'hello' }));
    log(`client connected (${wss.clients.size})`);
  });

  function broadcast(event) {
    stats.events += 1;
    const text = JSON.stringify(event);
    for (const client of wss.clients) {
      if (client.readyState === WebSocket.OPEN) client.send(text);
    }
    log(`${event.framework}/${event.session}/${event.agent} ${event.type}${event.tool ? ` ${event.tool}` : ''}`);
  }

  return {
    server,
    wss,
    stats,
    broadcast,
    listen: () =>
      new Promise((resolve) => {
        server.listen(port, host, () => resolve(server.address()));
      }),
    close: () =>
      new Promise((resolve) => {
        for (const client of wss.clients) client.terminate();
        wss.close(() => server.close(() => resolve()));
      }),
  };
}
