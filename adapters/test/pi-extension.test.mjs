// The Pi extension (adapters/pi/arena.ts) posts reduced events to the real bridge.
//
//   node --test adapters/test        (Node 22 or later; needs a Node that can import .ts files, or the test is skipped)

import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { ensureBridgeBuilt, openClient, startBridge, summarize } from './helpers.mjs';

before(() => ensureBridgeBuilt());

// The extension is TypeScript. Node strips types natively on recent versions. Skip if this one cannot.
async function loadExtension() {
  try {
    return (await import('../pi/arena.ts')).default;
  } catch (err) {
    if (err?.code === 'ERR_UNKNOWN_FILE_EXTENSION' || err?.code === 'ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX') return undefined;
    throw err;
  }
}

test('the extension registers handlers and forwards reduced events that the bridge maps', async (t) => {
  const bridge = await startBridge();
  process.env.ARENA_BRIDGE_HTTP = `http://127.0.0.1:${bridge.port}`;
  const client = await openClient(bridge.port);
  const posted = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (url, init) => {
    posted.push({ url: String(url), body: String(init?.body ?? '') });
    return realFetch(url, init);
  };
  try {
    const extension = await loadExtension();
    if (!extension) return t.skip('this Node version cannot import .ts files');

    const handlers = {};
    extension({ on: (name, handler) => (handlers[name] = handler) });
    assert.deepEqual(Object.keys(handlers).sort(), [
      'agent_end',
      'agent_start',
      'message_update',
      'session_start',
      'tool_execution_end',
      'tool_execution_start',
    ]);

    const ctx = { sessionManager: { getSessionId: () => 'sess-ext' } };
    await handlers.agent_start({}, ctx);
    await handlers.message_update({ assistantMessageEvent: { type: 'text_delta', delta: 'x' } }, ctx); // dropped
    await handlers.message_update({ assistantMessageEvent: { type: 'thinking_start' } }, ctx);
    await handlers.tool_execution_start({ toolCallId: 'c1', toolName: 'write', args: { path: '/repo/a.txt', content: 'SECRET FILE CONTENTS' } }, ctx);
    await handlers.tool_execution_end(
      { toolCallId: 'c1', toolName: 'write', isError: true, result: { content: [{ type: 'text', text: 'disk full' }], details: { big: 'x'.repeat(5000) } } },
      ctx,
    );
    await handlers.agent_end({ messages: ['a large payload'] }, ctx);
    const expected = ['thinking', 'thinking', 'tool_start:write:a.txt', 'tool_end(fail)', 'done'];
    await client.waitFor(expected.length);
    await new Promise((r) => setTimeout(r, 100));
    assert.deepEqual(client.events.map(summarize), expected);
    assert.equal(client.events.find((e) => e.type === 'tool_end').error, 'disk full');
    assert.ok(client.events.every((e) => e.session === 'sess-ext' && e.framework === 'pi'));

    const text = JSON.stringify(posted);
    assert.ok(!text.includes('SECRET FILE CONTENTS'), 'file contents are not forwarded');
    assert.ok(!text.includes('a large payload'), 'agent_end messages are not forwarded');
    assert.ok(posted.every((p) => p.url.endsWith('/hook/pi')));
  } finally {
    globalThis.fetch = realFetch;
    client.close();
    await bridge.stop();
  }
});
