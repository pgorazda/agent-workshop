// The OpenCode plugin (adapters/opencode/arena.js) posts a reduced event stream to the real bridge,
// which maps it to the same canonical events as the raw stream.
//
//   node --test 'adapters/test/*.test.mjs'        (Node 22 or later; builds the bridge with cargo when needed)

import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ensureBridgeBuilt, openClient, startBridge, summarize } from './helpers.mjs';

const rawEvents = () =>
  readFileSync(new URL('../../schema/examples/opencode-events.jsonl', import.meta.url), 'utf8')
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

before(() => ensureBridgeBuilt());

test('the plugin forwards a reduced event stream that the bridge maps to the expected events', async () => {
  const bridge = await startBridge();
  process.env.ARENA_BRIDGE_HTTP = `http://127.0.0.1:${bridge.port}`;
  const posted = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (url, init) => {
    posted.push({ url: String(url), body: String(init?.body ?? '') });
    return realFetch(url, init);
  };
  const client = await openClient(bridge.port);
  try {
    const { ArenaPlugin } = await import('../opencode/arena.js');
    const hooks = await ArenaPlugin();
    const raw = rawEvents();
    // An assistant message update and file edits are not forwarded.
    raw.push({ type: 'message.updated', properties: { info: { id: 'a', sessionID: 'ses_root', role: 'assistant' } } });
    raw.push({ type: 'file.edited', properties: { file: '/repo/app.py' } });
    for (const event of raw) await hooks.event({ event });
    const events = await client.waitFor(EXPECTED.length);
    await new Promise((r) => setTimeout(r, 100));
    assert.deepEqual(client.events.map(summarize), EXPECTED);
    assert.ok(events.every((e) => e.framework === 'opencode' && e.session === 'ses_root'));
    assert.ok(posted.every((p) => p.url.endsWith('/hook/opencode')));
    const text = JSON.stringify(posted);
    assert.ok(!text.includes('def add(a, b)'), 'tool output is not forwarded');
    assert.ok(!text.includes('Check the file first'), 'reasoning text is not forwarded');
    assert.ok(!text.includes('Looking'), 'text parts are not forwarded');
  } finally {
    globalThis.fetch = realFetch;
    client.close();
    await bridge.stop();
  }
});
