import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CATEGORIES, EVENT_TYPES, normalizeEvent, validateEvent } from '../src/schema.js';
import { categoryFor } from '../src/categories.js';

const base = { v: 1, framework: 'pi', session: 's1', type: 'thinking' };

test('normalizeEvent fills agent and ts and does not mutate the input', () => {
  const input = { ...base };
  const e = normalizeEvent(input);
  assert.equal(e.agent, 'main');
  assert.equal(typeof e.ts, 'number');
  assert.equal(input.agent, undefined);
});

test('normalizeEvent truncates long targets and can redact them', () => {
  const long = 'x'.repeat(500);
  assert.equal(normalizeEvent({ ...base, target: long }).target.length, 120);
  const redacted = normalizeEvent({ ...base, target: 'secret', error: 'secret' }, { redactTargets: true });
  assert.equal(redacted.target, undefined);
  assert.equal(redacted.error, undefined);
});

test('validateEvent accepts a minimal event and unknown types', () => {
  assert.deepEqual(validateEvent(normalizeEvent(base)), []);
  assert.deepEqual(validateEvent(normalizeEvent({ ...base, type: 'something_new' })), []);
});

test('validateEvent enforces per-type requirements', () => {
  const errs = (e) => validateEvent(normalizeEvent({ ...base, ...e }));
  assert.ok(errs({ type: 'tool_start' }).length >= 2);
  assert.deepEqual(errs({ type: 'tool_start', category: 'read', tool: 'Read' }), []);
  assert.ok(errs({ type: 'tool_end' }).some((m) => m.includes('ok')));
  assert.ok(errs({ type: 'subagent_start' }).some((m) => m.includes('id')));
  assert.ok(errs({ type: 'tool_start', category: 'nope', tool: 'x' }).some((m) => m.includes('category')));
  assert.ok(errs({ v: 2 }).some((m) => m.includes('v must be')));
  assert.ok(validateEvent('nope').length > 0);
});

test('categoryFor maps known tools across frameworks and falls back to other', () => {
  assert.equal(categoryFor('claude-code', 'Bash'), 'exec');
  assert.equal(categoryFor('opencode', 'bash'), 'exec');
  assert.equal(categoryFor('pi', 'read'), 'read');
  assert.equal(categoryFor('claude-code', 'WebFetch'), 'web');
  assert.equal(categoryFor('claude-code', 'Task'), 'delegate');
  assert.equal(categoryFor('claude-code', 'mcp__server__tool'), 'other');
  assert.equal(categoryFor('claude-code', undefined), 'other');
  for (const tool of ['Read', 'Grep', 'Edit', 'Bash', 'WebSearch', 'Task', 'TodoWrite', 'AskUserQuestion']) {
    assert.ok(CATEGORIES.includes(categoryFor('claude-code', tool)));
  }
});

test('schema/event.schema.json enums match the JS constants', async () => {
  const schema = JSON.parse(await readFile(new URL('../../schema/event.schema.json', import.meta.url), 'utf8'));
  assert.deepEqual(schema.properties.category.enum, CATEGORIES);
  const documented = schema.properties.type.description;
  for (const type of EVENT_TYPES) assert.ok(documented.includes(type), `${type} missing from schema docs`);
});
