// Tests of the scene timelines in godot/demo/: they follow the event schema (the bridge's own validation is checked in
// bridge/tests/demo_scenes.rs), and they tell a
// sensible story. The files are fixed: no tool makes them (see demo/README.md).

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const GODOT_DIR = fileURLToPath(new URL('..', import.meta.url));
const REPO_DIR = join(GODOT_DIR, '..');
const SCHEMA = JSON.parse(readFileSync(join(REPO_DIR, 'schema', 'event.schema.json'), 'utf8'));
const DEMO_DIR = join(GODOT_DIR, 'demo');
/** The made-up time of the first millisecond of every scene (ts = BASE_TS + t * 1000). */
const BASE_TS = 1767261600000;
const SCENES = ['session', 'multi', 'arenas', 'many', 'follow', 'ten', 'tour'];
const ARENA_SCENES = ['arenas', 'many', 'follow', 'ten'];
const filePath = (name) => join(DEMO_DIR, `${name}.json`);

const load = (name) => JSON.parse(readFileSync(filePath(name), 'utf8'));

/** The part of JSON Schema that schema/event.schema.json uses: type, const, enum, length, required, properties, allOf, if/then. */
function check(schema, value, path = '$') {
  const errors = [];
  const type = (v) => (Array.isArray(v) ? 'array' : v === null ? 'null' : typeof v);
  if ('const' in schema && value !== schema.const) errors.push(`${path}: must be ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(value)) errors.push(`${path}: must be one of ${schema.enum.join(', ')}`);
  if (schema.type && type(value) !== schema.type) errors.push(`${path}: must be ${schema.type}`);
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength) errors.push(`${path}: too short`);
    if (schema.maxLength !== undefined && value.length > schema.maxLength) errors.push(`${path}: too long`);
  }
  if (type(value) === 'object') {
    for (const key of schema.required ?? []) if (!(key in value)) errors.push(`${path}: missing ${key}`);
    for (const [key, sub] of Object.entries(schema.properties ?? {})) if (key in value) errors.push(...check(sub, value[key], `${path}.${key}`));
  }
  for (const rule of schema.allOf ?? []) {
    if (check(rule.if, value, path).length === 0) errors.push(...check(rule.then, value, path));
  }
  return errors;
}

test('the checker finds a wrong event (a test of the test)', () => {
  assert.ok(check(SCHEMA, { v: 1, framework: 'x', session: 's', agent: 'a', type: 'tool_start', ts: 1 }).length > 0, 'a tool_start needs category and tool');
  assert.ok(check(SCHEMA, { v: 2, framework: 'x', session: 's', agent: 'a', type: 'done', ts: 1 }).length > 0);
  assert.deepEqual(check(SCHEMA, { v: 1, framework: 'x', session: 's', agent: 'a', type: 'done', ts: 1 }), []);
});

for (const name of SCENES) {
  const timeline = load(name);

  test(`${name}: every event is valid by the schema`, () => {
    assert.ok(timeline.events.length > 10);
    for (const { event } of timeline.events) {
      assert.deepEqual(check(SCHEMA, event), [], JSON.stringify(event));
    }
  });

  test(`${name}: only fields of the schema, and no trace of a real path`, () => {
    const known = new Set(Object.keys(SCHEMA.properties));
    for (const { event } of timeline.events) {
      for (const key of Object.keys(event)) assert.ok(known.has(key), `${key} is not a field of the schema`);
      for (const text of [event.target, event.error, event.message, event.session]) {
        if (typeof text === 'string') assert.doesNotMatch(text, /[A-Za-z]:\\|\/Users\/|\/home\/|@/, text);
      }
    }
  });

  test(`${name}: times are in order, inside the duration, and the same as ts`, () => {
    // a scene may start with the agents that were there before it (a time below 0), but not before -10 s
    let last = -10;
    for (const { t, event } of timeline.events) {
      assert.ok(t >= last, `event at ${t} comes after ${last}`);
      assert.ok(t >= -10 && t <= timeline.duration, `${t} is inside -10..${timeline.duration}`);
      assert.equal(event.ts, BASE_TS + Math.round(t * 1000));
      last = t;
    }
    for (const input of timeline.inputs) assert.ok(input.t >= 0 && input.t <= timeline.duration);
  });

  test(`${name}: the options of the file are the ones that the client reads`, () => {
    assert.equal(typeof timeline.options, 'object');
    assert.ok(Number.isInteger(timeline.options.arena_size) && timeline.options.arena_size >= 0);
    for (const key of Object.keys(timeline.options)) assert.ok(['arena_size', 'follow', 'pace', 'mode', 'bar'].includes(key), key);
  });

  test(`${name}: each call ends once, after it started; each helper ends after it started`, () => {
    const open = new Map();
    for (const { event } of timeline.events) {
      const key = `${event.framework}|${event.session}|${event.agent}|${event.id}`;
      if (event.type === 'tool_start' || event.type === 'subagent_start') {
        assert.ok(!open.has(key), `${key} starts twice`);
        open.set(key, event.type);
      } else if (event.type === 'tool_end') {
        assert.equal(open.get(key), 'tool_start', `${key} ends without a start`);
        open.delete(key);
      } else if (event.type === 'subagent_end') {
        assert.equal(open.get(key), 'subagent_start', `${key} ends without a start`);
        open.delete(key);
      }
    }
    assert.equal(open.size, 0, `still open: ${[...open.keys()].join(', ')}`);
  });

  test(`${name}: the title and the shape of the file`, () => {
    assert.equal(typeof timeline.title, 'string');
    assert.ok(timeline.title.length > 3);
    assert.ok(timeline.duration > 10);
    assert.ok(Array.isArray(timeline.inputs));
  });

  test(`${name}: the scripted pointer, key caps and menus are well formed and inside the scene`, () => {
    for (const list of ['paths', 'keys', 'menus']) assert.ok(Array.isArray(timeline[list]), list);
    for (const { path, clicks } of timeline.paths) {
      assert.ok(path.length >= 2);
      let last = -1;
      for (const [t, x, y] of path) {
        assert.ok(t > last && t <= timeline.duration, `pointer time ${t}`);
        assert.ok(Number.isFinite(x) && Number.isFinite(y));
        last = t;
      }
      for (const click of clicks) assert.ok(click >= path[0][0] && click <= path.at(-1)[0] + 1e-9, `click at ${click} is on the path`);
    }
    for (const { t, label } of timeline.keys) assert.ok(t >= 0 && t <= timeline.duration && /^[A-Z]+$/.test(label), label);
    for (const { open, close } of timeline.menus) assert.ok(open >= 0 && close > open && close <= timeline.duration);
  });

  test(`${name}: the file ends with a line end`, () => {
    assert.ok(readFileSync(filePath(name), 'utf8').endsWith('}\n'));
  });
}

test('session: one Claude Code session with a failure, a helper, a prompt and a finished turn', () => {
  const { events } = load('session');
  const types = events.map((item) => item.event.type);
  assert.equal(types[0], 'session_start');
  assert.equal(types.at(-1), 'done');
  for (const type of ['thinking', 'waiting_permission', 'subagent_start', 'subagent_end']) assert.ok(types.includes(type), type);
  assert.ok(events.some((item) => item.event.type === 'tool_end' && item.event.ok === false), 'a failed call');
  assert.equal(new Set(events.map((item) => item.event.session)).size, 1);
  const categories = events.filter((item) => item.event.type === 'tool_start').map((item) => item.event.category);
  assert.deepEqual(categories, ['search', 'read', 'write', 'delegate', 'exec', 'write', 'exec', 'exec']);
});

test('multi: six agents of the four frameworks, with failures, prompts, a helper and a click', () => {
  const timeline = load('multi');
  const agents = new Set(timeline.events.map((item) => `${item.event.framework}|${item.event.session}`));
  assert.equal(agents.size, 6);
  assert.deepEqual([...new Set(timeline.events.map((item) => item.event.framework))].sort(), ['claude-code', 'hermes', 'opencode', 'pi']);
  const types = timeline.events.map((item) => item.event.type);
  for (const type of ['session_start', 'thinking', 'waiting_permission', 'subagent_start', 'done']) assert.ok(types.includes(type), type);
  assert.ok(timeline.events.some((item) => item.event.ok === false), 'a failed call');
  assert.deepEqual(timeline.inputs.map((input) => input.key ?? Object.keys(input.click)[0]), ['F', 'number']);
  assert.equal(timeline.inputs[1].click.number, 4);
});

test('the scenes with arenas: agents, inputs and the options of each', () => {
  const expected = { arenas: [9, 4], many: [34, 4], follow: [33, 4], ten: [157, 4] };
  for (const name of ARENA_SCENES) {
    const timeline = load(name);
    const agents = new Set(timeline.events.map((item) => `${item.event.framework}|${item.event.session}`));
    assert.equal(agents.size, expected[name][0], `${name}: agents`);
    assert.equal(timeline.options.arena_size, expected[name][1]);
    assert.ok(timeline.inputs.length >= 4, `${name}: the person's inputs are there`);
    for (const input of timeline.inputs) {
      const known = ['key', 'click', 'toggle', 'manual', 'pace'].some((field) => field in input);
      assert.ok(known, JSON.stringify(input));
    }
  }
  assert.deepEqual(load('follow').options.follow, { approval: true, fail: true, open: true, join: true, done: true, activity: true });
  assert.ok(load('ten').events.some((item) => item.t < 0), 'ten starts with agents that were there before the clip');
  assert.ok(load('arenas').events.every((item) => item.t >= 0), 'arenas starts empty');
});

test('the scenes that were scripted for a person carry what the old mockup drew', () => {
  // the keys of the arena scenes, the pointer of multi, the menus of follow
  assert.deepEqual(load('multi').paths.map((p) => p.clicks), [[22.6, 23.4]]);
  assert.deepEqual(load('arenas').keys, [{ t: 30.5, label: 'TAB' }, { t: 36, label: 'F' }]);
  assert.equal(load('arenas').paths.length, 2);
  assert.equal(load('many').keys.length, 8);
  assert.equal(load('ten').paths.length, 1);
  assert.deepEqual(load('follow').menus, [{ open: 16, close: 19.8 }, { open: 30, close: 30.9 }]);
  assert.deepEqual(load('session').paths, []);
  assert.deepEqual(load('tour').paths, []);
});

test('tour: 31 stops with the words of the old mockup, in order of the scene time, and four agents', () => {
  const timeline = load('tour');
  assert.equal(timeline.options.bar, 'cards');
  assert.equal(timeline.tour.stops.length, 31);
  assert.ok(Math.abs(timeline.tour.scene_end - timeline.duration) < 1e-9);
  let last = -1;
  const total = timeline.tour.stops.reduce((sum, stop) => sum + stop.dur, timeline.tour.scene_end);
  assert.ok(total > 270 && total < 290, `the clip is about 4.7 minutes: ${total}`);
  const kinds = new Set(['rect', 'ell', 'agent', 'card', 'helper', 'near']);
  for (const stop of timeline.tour.stops) {
    assert.ok(stop.at >= last && stop.at <= timeline.tour.scene_end);
    last = stop.at;
    assert.ok(['event', 'thing', 'title'].includes(stop.kind), stop.kind);
    assert.ok(stop.dur >= 4.4, `${stop.title} lasts ${stop.dur}`);
    assert.ok(stop.lines.length >= 1 && stop.lines.every((line) => typeof line === 'string'));
    for (const hole of stop.holes) assert.ok(Object.keys(hole).some((key) => kinds.has(key)), JSON.stringify(hole));
  }
  assert.deepEqual(timeline.tour.stops.map((stop) => stop.title).slice(0, 5), ['WELCOME', 'THE ARENA', 'EVENT: SESSION START', 'THE BAR', 'THE SOUND SWITCH']);
  assert.equal(timeline.tour.stops.at(-1).title, 'THAT IS ONE ARENA');
  assert.equal(new Set(timeline.events.map((item) => item.event.framework)).size, 4);
  const text = JSON.stringify(timeline.tour);
  assert.doesNotMatch(text, /[A-Za-z]:\\|\/Users\/|\/home\//);
});
