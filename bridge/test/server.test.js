import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { createBridge } from '../src/server.js';

async function start(options = {}) {
  const bridge = createBridge({ port: 0, ...options });
  const addr = await bridge.listen();
  return { bridge, http: `http://127.0.0.1:${addr.port}`, ws: `ws://127.0.0.1:${addr.port}/ws` };
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const messages = [];
    const waiters = [];
    socket.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      const waiter = waiters.shift();
      if (waiter) waiter(msg);
      else messages.push(msg);
    });
    socket.on('error', reject);
    socket.on('open', () =>
      resolve({
        socket,
        next: () =>
          new Promise((res, rej) => {
            if (messages.length) return res(messages.shift());
            const timer = setTimeout(() => rej(new Error('timed out waiting for a message')), 2000);
            waiters.push((m) => {
              clearTimeout(timer);
              res(m);
            });
          }),
      }),
    );
  });
}

const post = (url, body) =>
  fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });

test('a client gets hello, then events posted to /event', async () => {
  const { bridge, http, ws } = await start();
  const client = await connect(ws);
  try {
    assert.equal((await client.next()).type, 'hello');
    const res = await post(`${http}/event`, { v: 1, framework: 'pi', session: 's1', type: 'thinking' });
    assert.equal(res.status, 202);
    const event = await client.next();
    assert.equal(event.type, 'thinking');
    assert.equal(event.agent, 'main');
    assert.equal(typeof event.ts, 'number');
  } finally {
    client.socket.close();
    await bridge.close();
  }
});

test('invalid events are rejected with 400 and not broadcast; valid ones in the same batch pass', async () => {
  const { bridge, http, ws } = await start();
  const client = await connect(ws);
  try {
    await client.next(); // hello
    const res = await post(`${http}/event`, [
      { v: 1, framework: 'pi', session: 's1', type: 'tool_start' },
      { v: 1, framework: 'pi', session: 's1', type: 'done' },
    ]);
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.accepted, 1);
    assert.equal(body.rejected[0].index, 0);
    assert.equal((await client.next()).type, 'done');
    assert.equal(bridge.stats.rejected, 1);
  } finally {
    client.socket.close();
    await bridge.close();
  }
});

test('Claude Code hook payloads are mapped and broadcast; the hook response is empty', async () => {
  const { bridge, http, ws } = await start();
  const client = await connect(ws);
  try {
    await client.next(); // hello
    const res = await post(`${http}/hook/claude-code`, {
      hook_event_name: 'PreToolUse',
      session_id: 'c1',
      tool_name: 'Bash',
      tool_input: { command: 'npm test' },
    });
    assert.equal(res.status, 204);
    const event = await client.next();
    assert.deepEqual(
      { type: event.type, category: event.category, target: event.target, framework: event.framework },
      { type: 'tool_start', category: 'exec', target: 'npm test', framework: 'claude-code' },
    );
  } finally {
    client.socket.close();
    await bridge.close();
  }
});

test('redactTargets drops targets and errors before broadcast', async () => {
  const { bridge, http, ws } = await start({ redactTargets: true });
  const client = await connect(ws);
  try {
    await client.next();
    await post(`${http}/hook/claude-code`, {
      hook_event_name: 'PreToolUse',
      session_id: 'c1',
      tool_name: 'Bash',
      tool_input: { command: 'echo secret' },
    });
    const event = await client.next();
    assert.equal(event.target, undefined);
    assert.equal(event.tool, 'Bash');
  } finally {
    client.socket.close();
    await bridge.close();
  }
});

test('malformed JSON gives 400, unknown routes 404, and /health reports counters', async () => {
  const { bridge, http } = await start();
  try {
    const bad = await fetch(`${http}/event`, { method: 'POST', body: '{nope' });
    assert.equal(bad.status, 400);
    assert.equal((await fetch(`${http}/nowhere`)).status, 404);
    const health = await (await fetch(`${http}/health`)).json();
    assert.equal(health.ok, true);
    assert.equal(health.schema, 1);
  } finally {
    await bridge.close();
  }
});
