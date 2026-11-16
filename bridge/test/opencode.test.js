import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createOpenCodeAdapter } from '../src/adapters/opencode.js';
import { createBridge } from '../src/server.js';
import { normalizeEvent, validateEvent } from '../src/schema.js';
import { connectWs, summarize } from './helpers.js';

const rawEvents = async () =>
  (await readFile(new URL('../../schema/examples/opencode-events.jsonl', import.meta.url), 'utf8'))
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));

const EXPECTED = [
  'session_start',
  'thinking', // user message (the duplicate update is ignored)
  'thinking', // reasoning part
  'tool_start:read:app.py', // 'pending' is skipped; 'running' starts the tool
  'tool_end',
  'tool_start:exec:pytest -q',
  'tool_end(fail)',
  'tool_start:delegate:Investigate failure',
  'subagent_start', // child session created
  'tool_start:search:fixture', // child session activity
  'tool_end',
  'subagent_end', // child session idle
  'tool_end', // the task tool completes
  'waiting_permission',
  'tool_start:exec:rm -rf build',
  'tool_end',
  'done', // root session idle
];

function run(events) {
  const adapter = createOpenCodeAdapter();
  return events.flatMap((event) => adapter.fromPayload({ event }));
}

test('OpenCode events map to the expected Agent Workshop events and every event is valid', async () => {
  const out = run(await rawEvents());
  assert.deepEqual(out.map(summarize), EXPECTED);
  for (const e of out) assert.deepEqual(validateEvent(normalizeEvent(e)), [], JSON.stringify(e));
  assert.ok(out.every((e) => e.framework === 'opencode' && e.session === 'ses_root'));
});

test('subagent activity is reported under the root session with the child session as agent', async () => {
  const out = run(await rawEvents());
  const start = out.find((e) => e.type === 'subagent_start');
  const end = out.find((e) => e.type === 'subagent_end');
  const childTools = out.filter((e) => e.agent === 'ses_child');
  assert.equal(start.id, 'ses_child');
  assert.equal(start.agent, 'main');
  assert.equal(end.id, 'ses_child');
  assert.deepEqual(childTools.map((e) => e.type), ['tool_start', 'tool_end']);
  assert.ok(out.filter((e) => e.agent === 'main').length > childTools.length);
});

test('a failed tool part carries its error text', async () => {
  const out = run(await rawEvents());
  const failed = out.find((e) => e.type === 'tool_end' && e.ok === false);
  assert.equal(failed.id, 'call_2');
  assert.equal(failed.error, 'exit code 1');
});

test('a tool first seen as completed still produces start and end; repeats are ignored', () => {
  const part = (status) => ({
    type: 'message.part.updated',
    properties: { part: { type: 'tool', id: 'p', sessionID: 's', callID: 'c', tool: 'read', state: { status, input: { filePath: '/a/b.txt' } } } },
  });
  const out = run([part('completed'), part('completed'), part('running')]);
  assert.deepEqual(out.map(summarize), ['tool_start:read:b.txt', 'tool_end']);
});

test('errors, retries, deletion and noise', () => {
  const adapter = createOpenCodeAdapter();
  const one = (event) => adapter.fromEvent(event);
  assert.equal(one({ type: 'session.error', properties: { sessionID: 's', error: { name: 'ApiError' } } })[0].message, 'ApiError');
  assert.equal(one({ type: 'session.status', properties: { sessionID: 's', status: { type: 'retry', attempt: 2 } } })[0].type, 'error');
  assert.deepEqual(one({ type: 'session.status', properties: { sessionID: 's', status: { type: 'busy' } } }), []);
  assert.deepEqual(one({ type: 'file.edited', properties: {} }), []);
  assert.deepEqual(one({ type: 'session.idle', properties: {} }), []);
  assert.deepEqual(one(null), []);

  // A child session deleted while still open ends its subagent exactly once.
  adapter.fromEvent({ type: 'session.created', properties: { info: { id: 'root' } } });
  adapter.fromEvent({ type: 'session.created', properties: { info: { id: 'kid', parentID: 'root' } } });
  const gone = adapter.fromEvent({ type: 'session.deleted', properties: { info: { id: 'kid' } } });
  assert.deepEqual(gone.map((e) => [e.type, e.id]), [['subagent_end', 'kid']]);
  assert.deepEqual(adapter.fromEvent({ type: 'session.idle', properties: { sessionID: 'kid' } }).map((e) => e.type), ['done']);
});

test('a bare event (not wrapped in { event }) is accepted too', () => {
  const adapter = createOpenCodeAdapter();
  const out = adapter.fromPayload({ type: 'session.idle', properties: { sessionID: 's' } });
  assert.equal(out[0].type, 'done');
});

test('plugin: forwards a reduced event stream that maps to the same Agent Workshop events', async () => {
  const posted = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    posted.push({ url: String(url), body: JSON.parse(init.body) });
    return new Response(null, { status: 204 });
  };
  try {
    const { ArenaPlugin } = await import('../../adapters/opencode/arena.js');
    const hooks = await ArenaPlugin();
    const raw = await rawEvents();
    // An assistant message update and file edits are not forwarded.
    raw.push({ type: 'message.updated', properties: { info: { id: 'a', sessionID: 'ses_root', role: 'assistant' } } });
    raw.push({ type: 'file.edited', properties: { file: '/repo/app.py' } });
    for (const event of raw) await hooks.event({ event });
    await new Promise((resolve) => setTimeout(resolve, 50)); // let the plugin's queue drain

    assert.ok(posted.every((p) => p.url.endsWith('/hook/opencode')));
    const text = JSON.stringify(posted);
    assert.ok(!text.includes('def add(a, b)'), 'tool output is not forwarded');
    assert.ok(!text.includes('Check the file first'), 'reasoning text is not forwarded');
    assert.ok(!text.includes('Looking'), 'text parts are not forwarded');

    const viaPlugin = createOpenCodeAdapter();
    const out = posted.flatMap((p) => viaPlugin.fromPayload(p.body));
    assert.deepEqual(out.map(summarize), EXPECTED);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('POST /hook/opencode reaches WebSocket clients', async () => {
  const bridge = createBridge({ port: 0 });
  const addr = await bridge.listen();
  const client = await connectWs(`ws://127.0.0.1:${addr.port}/ws`);
  try {
    await client.next(); // hello
    const res = await fetch(`http://127.0.0.1:${addr.port}/hook/opencode`, {
      method: 'POST',
      body: JSON.stringify({ event: { type: 'session.idle', properties: { sessionID: 's9' } } }),
    });
    assert.equal(res.status, 204);
    const event = await client.next();
    assert.deepEqual([event.framework, event.session, event.type], ['opencode', 's9', 'done']);
  } finally {
    client.socket.close();
    await bridge.close();
  }
});
