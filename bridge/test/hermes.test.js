import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createHermesAdapter } from '../src/adapters/hermes.js';
import { createBridge } from '../src/server.js';
import { categoryFor } from '../src/categories.js';
import { describeTarget } from '../src/targets.js';
import { normalizeEvent, validateEvent } from '../src/schema.js';
import { connectWs, summarize } from './helpers.js';

const payloads = async () =>
  (await readFile(new URL('../../schema/examples/hermes-hooks.jsonl', import.meta.url), 'utf8'))
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));

const EXPECTED = [
  'session_start',
  'thinking', // first API call of the turn
  'tool_start:read:app.py',
  'tool_end',
  'tool_start:exec:rm -rf build',
  'waiting_permission', // approval request carries no session id
  'tool_end',
  'tool_start:exec:pytest -q',
  'tool_end(fail)',
  'tool_start:delegate:Investigate the failing test',
  'subagent_start',
  'tool_start:search:fixture', // the subagent's own call
  'tool_end',
  'subagent_end',
  'tool_end', // delegate_task completes
  'tool_start:web:https://example.com/docs',
  'tool_end',
  'done',
];

function run(list) {
  const adapter = createHermesAdapter();
  return list.flatMap((p) => adapter.fromHook(p));
}

test('Hermes hook payloads map to the expected events and every event is valid', async () => {
  const out = run(await payloads());
  assert.deepEqual(out.map(summarize), EXPECTED);
  for (const e of out) assert.deepEqual(validateEvent(normalizeEvent(e)), [], JSON.stringify(e));
  assert.ok(out.every((e) => e.framework === 'hermes' && e.session === 'sess_1'));
});

test('approvals without a session id are attributed to the session seen last', async () => {
  const out = run(await payloads());
  const ask = out.find((e) => e.type === 'waiting_permission');
  assert.equal(ask.session, 'sess_1');
  assert.equal(ask.agent, 'main');
  assert.equal(ask.message, 'recursive delete');
  assert.ok(!JSON.stringify(out).includes('rm -rf build') || out.some((e) => e.target === 'rm -rf build'));
});

test('subagent activity is reported under the parent session with the child session as agent', async () => {
  const out = run(await payloads());
  const start = out.find((e) => e.type === 'subagent_start');
  const end = out.find((e) => e.type === 'subagent_end');
  const childEvents = out.filter((e) => e.agent === 'sess_child');
  assert.deepEqual([start.id, start.agent, start.session], ['sess_child', 'main', 'sess_1']);
  assert.deepEqual([end.id, end.agent, end.session], ['sess_child', 'main', 'sess_1']);
  assert.deepEqual(childEvents.map((e) => e.type), ['tool_start', 'tool_end']);
  // The child's own session start and end do not create extra events.
  assert.equal(out.filter((e) => e.type === 'session_start').length, 1);
  assert.equal(out.filter((e) => e.type === 'done').length, 1);
});

test('a failed tool carries its error message; status and error_type decide the outcome', () => {
  const adapter = createHermesAdapter();
  const end = (extra) =>
    adapter.fromHook({ hook_event_name: 'post_tool_call', tool_name: 'terminal', session_id: 's', extra })[0];
  assert.equal(end({ status: 'ok' }).ok, true);
  const bad = end({ status: 'error', error_message: 'exit code 1' });
  assert.deepEqual([bad.ok, bad.error], [false, 'exit code 1']);
  assert.deepEqual([end({ status: 'blocked' }).ok, end({ status: 'blocked' }).error], [false, 'blocked']);
  assert.equal(end({ error_type: 'ValueError' }).ok, false); // no status field: fall back to error_type
  assert.equal(end({}).ok, true);
});

test('only the first API call of a turn means thinking; interrupted turns are errors, not done', () => {
  const adapter = createHermesAdapter();
  const hook = (hook_event_name, extra = {}) => adapter.fromHook({ hook_event_name, session_id: 's', extra });
  assert.equal(hook('pre_api_request', { api_call_count: 1 }).length, 1);
  assert.equal(hook('pre_api_request', { api_call_count: 2 }).length, 0);
  assert.equal(hook('pre_api_request', {}).length, 0);
  assert.equal(hook('on_session_end', { completed: true })[0].type, 'done');
  const interrupted = hook('on_session_end', { completed: false, interrupted: true })[0];
  assert.deepEqual([interrupted.type, interrupted.message], ['error', 'interrupted']);
  assert.equal(hook('api_request_error', { error_type: 'RateLimit' })[0].message, 'RateLimit');
});

test('unknown hooks, junk and missing fields produce nothing', () => {
  const adapter = createHermesAdapter();
  assert.deepEqual(adapter.fromHook(null), []);
  assert.deepEqual(adapter.fromHook({ hook_event_name: 'pre_llm_call', session_id: 's', extra: { conversation_history: [] } }), []);
  assert.deepEqual(adapter.fromHook({ hook_event_name: 'pre_tool_call', session_id: 's' }), []);
  assert.deepEqual(adapter.fromHook({ hook_event_name: 'subagent_start', session_id: 's', extra: {} }), []);
  // Without any session id, a fresh adapter falls back to a default; after one is seen it reuses it.
  assert.equal(createHermesAdapter().fromHook({ hook_event_name: 'on_session_end', extra: {} })[0].session, 'hermes');
  assert.equal(adapter.fromHook({ hook_event_name: 'on_session_end', extra: {} })[0].session, 's');
});

test('Hermes tool names map to categories', () => {
  const cases = {
    terminal: 'exec',
    execute_code: 'exec',
    read_file: 'read',
    write_file: 'write',
    patch: 'write',
    search_files: 'search',
    web_search: 'web',
    web_extract: 'web',
    browser_click: 'web',
    delegate_task: 'delegate',
    todo: 'think',
    clarify: 'ask_permission',
    image_generate: 'other',
  };
  for (const [tool, category] of Object.entries(cases)) assert.equal(categoryFor('hermes', tool), category, tool);
  assert.equal(categoryFor('claude-code', 'browser_click'), 'other', 'prefix rules are per framework');
});

test('describeTarget handles Hermes arguments', () => {
  assert.equal(describeTarget({ goal: 'Do the thing' }), 'Do the thing');
  assert.equal(describeTarget({ urls: ['https://a.test', 'https://b.test'] }), 'https://a.test');
  assert.equal(describeTarget({ path: '/a/b.py' }), 'b.py');
  assert.equal(describeTarget({ pattern: 'x', path: 'src' }), 'x');
});

test('POST /hook/hermes reaches WebSocket clients, including a payload over 1 MB', async () => {
  const bridge = createBridge({ port: 0 });
  const addr = await bridge.listen();
  const client = await connectWs(`ws://127.0.0.1:${addr.port}/ws`);
  try {
    await client.next(); // hello
    const big = {
      hook_event_name: 'post_tool_call',
      tool_name: 'read_file',
      session_id: 's7',
      extra: { tool_call_id: 'c', status: 'ok', result: 'x'.repeat(2_000_000) },
    };
    const res = await fetch(`http://127.0.0.1:${addr.port}/hook/hermes`, { method: 'POST', body: JSON.stringify(big) });
    assert.equal(res.status, 204);
    const event = await client.next();
    assert.deepEqual([event.framework, event.session, event.type, event.ok], ['hermes', 's7', 'tool_end', true]);
  } finally {
    client.socket.close();
    await bridge.close();
  }
});

test('arena-hook.sh forwards stdin to the bridge, and stays silent with exit 0 when the bridge is down', async (t) => {
  const script = fileURLToPath(new URL('../../adapters/hermes/arena-hook.sh', import.meta.url));
  // Windows has no executable bit and cannot run a .sh file directly, so it starts the script with bash.
  const windows = process.platform === 'win32';
  if (!windows) assert.ok((await stat(script)).mode & 0o100, 'the script is executable');

  const run = (url, input) =>
    new Promise((resolve, reject) => {
      const [command, args] = windows ? ['bash', [script.replaceAll('\\', '/')]] : [script, []];
      const child = spawn(command, args, { env: { ...process.env, ARENA_BRIDGE_HTTP: url }, stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '';
      child.stdout.on('data', (d) => (out += d));
      child.stderr.on('data', (d) => (out += d));
      child.on('error', reject);
      child.on('close', (code) => resolve({ code, out }));
      child.stdin.end(input);
    });

  const bridge = createBridge({ port: 0 });
  const addr = await bridge.listen();
  const client = await connectWs(`ws://127.0.0.1:${addr.port}/ws`);
  const payload = JSON.stringify({
    hook_event_name: 'pre_tool_call',
    tool_name: 'terminal',
    tool_input: { command: 'make test' },
    session_id: 's1',
    extra: { tool_call_id: 'c1' },
  });
  try {
    await client.next(); // hello
    const ok = await run(`http://127.0.0.1:${addr.port}/`, payload); // a trailing slash is tolerated
    assert.deepEqual(ok, { code: 0, out: '' });
    assert.equal(summarize(await client.next()), 'tool_start:exec:make test');

    const offline = await run('http://127.0.0.1:1', payload);
    assert.deepEqual(offline, { code: 0, out: '' });
  } catch (err) {
    if (err?.code === 'ENOENT') return t.skip('curl or sh is not available');
    throw err;
  } finally {
    client.socket.close();
    await bridge.close();
  }
});
