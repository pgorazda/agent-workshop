import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createPiAdapter, piEventToArena } from '../src/adapters/pi.js';
import { createBridge } from '../src/server.js';
import { normalizeEvent, validateEvent } from '../src/schema.js';
import { connectWs, summarize } from './helpers.js';

const fixture = async () =>
  (await readFile(new URL('../../schema/examples/pi-json-mode.jsonl', import.meta.url), 'utf8'))
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));

const EXPECTED = [
  'session_start',
  'thinking', // agent_start
  'thinking', // thinking_start
  'tool_start:read:app.py',
  'tool_end',
  'tool_start:write:app.py',
  'tool_end',
  'tool_start:exec:pytest -q',
  'tool_end(fail)',
  'tool_start:delegate:Investigate the failure',
  'subagent_start',
  'tool_end',
  'subagent_end',
  'tool_start:search:fixture',
  'tool_end',
  'error',
  'done',
];

test('Pi JSON-mode stream maps to the expected events and every event is valid', async () => {
  const events = [];
  let session = 'fallback';
  for (const event of await fixture()) {
    if (event.type === 'session') session = event.id;
    events.push(...piEventToArena(session, event));
  }
  assert.deepEqual(events.map(summarize), EXPECTED);
  for (const e of events) assert.deepEqual(validateEvent(normalizeEvent(e)), [], JSON.stringify(e));
  assert.ok(events.every((e) => e.framework === 'pi' && e.session === 'pi-session-1'));
});

test('failed tools carry the error text; ok tools do not', async () => {
  const events = [];
  for (const event of await fixture()) events.push(...piEventToArena('s', event));
  const ends = events.filter((e) => e.type === 'tool_end');
  assert.equal(ends.find((e) => e.id === 'c3').ok, false);
  assert.match(ends.find((e) => e.id === 'c3').error, /exited with code 1/);
  assert.equal(ends.find((e) => e.id === 'c1').error, undefined);
});

test('streaming noise produces no events', () => {
  for (const type of ['turn_start', 'turn_end', 'message_start', 'message_end', 'tool_execution_update', 'queue_update']) {
    assert.deepEqual(piEventToArena('s', { type }), [], type);
  }
  const delta = { type: 'message_update', assistantMessageEvent: { type: 'text_delta', delta: 'x' } };
  assert.deepEqual(piEventToArena('s', delta), []);
  assert.deepEqual(piEventToArena('s', null), []);
  assert.deepEqual(piEventToArena('s', { type: 'tool_execution_start' }), []);
});

test('fromPayload reads { session, event } and falls back to a default session', () => {
  const adapter = createPiAdapter();
  assert.equal(adapter.fromPayload({ session: 'abc', event: { type: 'agent_end' } })[0].session, 'abc');
  assert.equal(adapter.fromPayload({ event: { type: 'agent_end' } })[0].session, 'pi');
  assert.deepEqual(adapter.fromPayload(null), []);
});

test('POST /hook/pi reaches WebSocket clients', async () => {
  const bridge = createBridge({ port: 0 });
  const addr = await bridge.listen();
  const client = await connectWs(`ws://127.0.0.1:${addr.port}/ws`);
  try {
    await client.next(); // hello
    const res = await fetch(`http://127.0.0.1:${addr.port}/hook/pi`, {
      method: 'POST',
      body: JSON.stringify({ session: 's1', event: { type: 'tool_execution_start', toolCallId: 'x', toolName: 'bash', args: { command: 'ls' } } }),
    });
    assert.equal(res.status, 204);
    assert.equal(summarize(await client.next()), 'tool_start:exec:ls');
  } finally {
    client.socket.close();
    await bridge.close();
  }
});

test('`cli ingest pi` forwards a piped JSON stream (with --tee) and survives a missing bridge', async () => {
  const bridge = createBridge({ port: 0 });
  const addr = await bridge.listen();
  const client = await connectWs(`ws://127.0.0.1:${addr.port}/ws`);
  const input = (await readFile(new URL('../../schema/examples/pi-json-mode.jsonl', import.meta.url), 'utf8')) + 'not json\n';
  const cli = fileURLToPath(new URL('../src/cli.js', import.meta.url));

  const run = (url) =>
    new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [cli, 'ingest', 'pi', '--tee', '--url', url], { stdio: ['pipe', 'pipe', 'inherit'] });
      let out = '';
      child.stdout.on('data', (d) => (out += d));
      child.on('error', reject);
      child.on('close', (code) => resolve({ code, out }));
      child.stdin.end(input);
    });

  try {
    await client.next(); // hello
    const { code, out } = await run(`http://127.0.0.1:${addr.port}`);
    assert.equal(code, 0);
    assert.ok(out.includes('"type":"agent_start"'), '--tee copies lines to stdout');
    const seen = [];
    for (let i = 0; i < EXPECTED.length; i += 1) seen.push(summarize(await client.next()));
    assert.deepEqual(seen, EXPECTED);

    const offline = await run('http://127.0.0.1:1'); // nothing listens there
    assert.equal(offline.code, 0, 'fails open when the bridge is down');
  } finally {
    client.socket.close();
    await bridge.close();
  }
});
