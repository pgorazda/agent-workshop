import test from 'node:test';
import assert from 'node:assert/strict';
import { createPiAdapter } from '../src/adapters/pi.js';
import { summarize } from './helpers.js';

// The extension is TypeScript. Node strips types natively on recent versions; skip if this one cannot.
async function loadExtension() {
  try {
    return (await import('../../adapters/pi/arena.ts')).default;
  } catch (err) {
    if (err?.code === 'ERR_UNKNOWN_FILE_EXTENSION' || err?.code === 'ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX') return undefined;
    throw err;
  }
}

test('extension registers handlers and forwards reduced events that the adapter maps', async (t) => {
  const extension = await loadExtension();
  if (!extension) return t.skip('this Node version cannot import .ts files');

  const handlers = {};
  extension({ on: (name, handler) => (handlers[name] = handler) });
  assert.deepEqual(
    Object.keys(handlers).sort(),
    ['agent_end', 'agent_start', 'message_update', 'session_start', 'tool_execution_end', 'tool_execution_start'],
  );

  const posted = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    posted.push({ url: String(url), body: JSON.parse(init.body) });
    return new Response(null, { status: 204 });
  };
  try {
    const ctx = { sessionManager: { getSessionId: () => 'sess-ext' } };
    await handlers.agent_start({}, ctx);
    await handlers.message_update({ assistantMessageEvent: { type: 'text_delta', delta: 'x' } }, ctx); // dropped
    await handlers.message_update({ assistantMessageEvent: { type: 'thinking_start' } }, ctx);
    await handlers.tool_execution_start(
      { toolCallId: 'c1', toolName: 'write', args: { path: '/repo/a.txt', content: 'SECRET FILE CONTENTS' } },
      ctx,
    );
    await handlers.tool_execution_end(
      { toolCallId: 'c1', toolName: 'write', isError: true, result: { content: [{ type: 'text', text: 'disk full' }], details: { big: 'x'.repeat(5000) } } },
      ctx,
    );
    await handlers.agent_end({ messages: ['a large payload'] }, ctx);
    await new Promise((resolve) => setTimeout(resolve, 50));

    const text = JSON.stringify(posted);
    assert.ok(!text.includes('SECRET FILE CONTENTS'), 'file contents are not forwarded');
    assert.ok(!text.includes('a large payload'), 'agent_end messages are not forwarded');
    assert.ok(posted.every((p) => p.url.endsWith('/hook/pi') && p.body.session === 'sess-ext'));

    const adapter = createPiAdapter();
    const out = posted.flatMap((p) => adapter.fromPayload(p.body));
    assert.deepEqual(out.map(summarize), ['thinking', 'thinking', 'tool_start:write:a.txt', 'tool_end(fail)', 'done']);
    assert.equal(out.find((e) => e.type === 'tool_end').error, 'disk full');
  } finally {
    globalThis.fetch = realFetch;
  }
});
