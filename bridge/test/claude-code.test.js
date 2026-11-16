import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createClaudeCodeAdapter, transcriptToEvents, describeTarget } from '../src/adapters/claude-code.js';
import { normalizeEvent, validateEvent } from '../src/schema.js';

const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: 'c1', ...extra });
const assertAllValid = (events) => {
  for (const e of events) assert.deepEqual(validateEvent(normalizeEvent(e)), [], JSON.stringify(e));
};

test('PreToolUse becomes tool_start with category and target', () => {
  const adapter = createClaudeCodeAdapter();
  const events = adapter.fromHook(
    hook('PreToolUse', { tool_name: 'Edit', tool_use_id: 'tu1', tool_input: { file_path: '/repo/src/app.py' } }),
  );
  assert.equal(events.length, 1);
  assert.deepEqual(
    { type: events[0].type, category: events[0].category, tool: events[0].tool, target: events[0].target, id: events[0].id },
    { type: 'tool_start', category: 'write', tool: 'Edit', target: 'app.py', id: 'tu1' },
  );
  assertAllValid(events);
});

test('PostToolUse maps failure heuristics to ok=false', () => {
  const adapter = createClaudeCodeAdapter();
  const ok = adapter.fromHook(hook('PostToolUse', { tool_name: 'Bash', tool_response: { stdout: 'fine' } }));
  const bad = adapter.fromHook(hook('PostToolUse', { tool_name: 'Bash', tool_response: { is_error: true, error: 'boom' } }));
  const failure = adapter.fromHook(hook('PostToolUseFailure', { tool_name: 'Bash', error: 'denied' }));
  assert.equal(ok[0].ok, true);
  assert.equal(bad[0].ok, false);
  assert.equal(bad[0].error, 'boom');
  assert.equal(failure[0].ok, false);
  assertAllValid([...ok, ...bad, ...failure]);
});

test('Task opens a subagent and SubagentStop closes it', () => {
  const adapter = createClaudeCodeAdapter();
  const start = adapter.fromHook(hook('PreToolUse', { tool_name: 'Task', tool_use_id: 'sub1', tool_input: { description: 'x' } }));
  assert.deepEqual(start.map((e) => e.type), ['tool_start', 'subagent_start']);
  assert.equal(start[1].id, 'sub1');
  const stop = adapter.fromHook(hook('SubagentStop'));
  assert.deepEqual([stop[0].type, stop[0].id], ['subagent_end', 'sub1']);
  assertAllValid([...start, ...stop]);
});

test('Notification about permission becomes waiting_permission; other notifications are ignored', () => {
  const adapter = createClaudeCodeAdapter();
  const ask = adapter.fromHook(hook('Notification', { message: 'Claude needs your permission to use Bash' }));
  assert.equal(ask[0].type, 'waiting_permission');
  assert.deepEqual(adapter.fromHook(hook('Notification', { message: 'Claude is waiting for your input' })), []);
});

test('Stop, SessionStart, UserPromptSubmit and unknown hooks', () => {
  const adapter = createClaudeCodeAdapter();
  assert.equal(adapter.fromHook(hook('Stop'))[0].type, 'done');
  assert.equal(adapter.fromHook(hook('SessionStart'))[0].type, 'session_start');
  assert.equal(adapter.fromHook(hook('UserPromptSubmit'))[0].type, 'thinking');
  assert.deepEqual(adapter.fromHook(hook('PreCompact')), []);
  assert.deepEqual(adapter.fromHook(null), []);
  assert.deepEqual(adapter.fromHook(hook('PreToolUse')), []);
});

test('describeTarget picks the most useful field', () => {
  assert.equal(describeTarget({ file_path: '/a/b/c.txt' }), 'c.txt');
  assert.equal(describeTarget({ command: 'ls -la\necho hi' }), 'ls -la');
  assert.equal(describeTarget({ pattern: 'foo' }), 'foo');
  assert.equal(describeTarget({ url: 'https://x.test' }), 'https://x.test');
  assert.equal(describeTarget(null), undefined);
  assert.equal(describeTarget({}), undefined);
});

test('transcript replay produces a valid, ordered event stream', async () => {
  const text = await readFile(new URL('../../schema/examples/claude-code-transcript.jsonl', import.meta.url), 'utf8');
  const events = transcriptToEvents(text);
  assertAllValid(events);

  const summary = events.map((e) => (e.type === 'tool_start' ? `${e.type}:${e.category}` : e.type));
  assert.deepEqual(summary, [
    'thinking', // user prompt
    'thinking', // assistant thinking block
    'tool_start:search',
    'tool_end',
    'tool_start:read',
    'tool_end',
    'tool_start:write',
    'tool_end',
    'tool_start:exec',
    'tool_end',
    'tool_start:delegate',
    'subagent_start',
    'tool_end',
    'subagent_end',
    'tool_start:web',
    'tool_end',
    'done',
  ]);

  const failed = events.filter((e) => e.type === 'tool_end' && e.ok === false);
  assert.equal(failed.length, 1);
  assert.equal(failed[0].id, 'toolu_4');
  assert.ok(events.every((e) => e.session === 'demo-1'));
  for (let i = 1; i < events.length; i += 1) assert.ok(events[i].ts >= events[i - 1].ts, 'timestamps are monotonic');
});

test('transcript replay skips garbage and returns nothing for empty input', () => {
  assert.deepEqual(transcriptToEvents(''), []);
  assert.deepEqual(transcriptToEvents('not json\n{"type":"summary"}\n'), []);
});
