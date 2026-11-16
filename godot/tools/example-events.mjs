// Turns the example sessions in schema/examples/ into canonical schema v1 events.
//
// The example files are in the native formats of four frameworks. The bridge adapters map them to
// canonical events. This module runs the adapters, so the Godot tests can use the result as a fixture.
//
//   node tools/example-events.mjs          write godot/test/fixtures/*.events.jsonl
//   node tools/example-events.mjs --check  fail when the files are out of date

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { transcriptToEvents } from '../../bridge/src/adapters/claude-code.js';
import { createHermesAdapter } from '../../bridge/src/adapters/hermes.js';
import { createOpenCodeAdapter } from '../../bridge/src/adapters/opencode.js';
import { piEventToArena } from '../../bridge/src/adapters/pi.js';
import { normalizeEvent, validateEvent } from '../../bridge/src/schema.js';

// 2026-01-01T10:00:00Z, the time of the example sessions.
const FIRST_TS = 1767261600000;

const EXAMPLES = new URL('../../schema/examples/', import.meta.url);
export const FIXTURES = new URL('../test/fixtures/', import.meta.url);

const lines = (file) =>
  readFileSync(new URL(file, EXAMPLES), 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));

/** Canonical events of each example, in order. The key is the example name. */
export function exampleEvents() {
  const claude = transcriptToEvents(readFileSync(new URL('claude-code-transcript.jsonl', EXAMPLES), 'utf8'));

  const hermesAdapter = createHermesAdapter();
  const hermes = lines('hermes-hooks.jsonl').flatMap((payload) => hermesAdapter.fromHook(payload));

  const openCodeAdapter = createOpenCodeAdapter();
  const opencode = lines('opencode-events.jsonl').flatMap((event) => openCodeAdapter.fromPayload({ event }));

  let session = 'pi';
  const pi = [];
  for (const event of lines('pi-json-mode.jsonl')) {
    if (event.type === 'session') session = event.id;
    pi.push(...piEventToArena(session, event));
  }

  const result = { 'claude-code': claude, hermes, opencode, pi };
  for (const [name, events] of Object.entries(result)) {
    // Some adapters stamp events with the current time. A fixed time keeps the fixture the same on each run.
    result[name] = events.map((event, i) => normalizeEvent({ ts: FIRST_TS + i * 500, ...event }));
    for (const event of result[name]) {
      const problems = validateEvent(event);
      if (problems.length > 0) throw new Error(`${name}: invalid event ${JSON.stringify(event)}: ${problems.join('; ')}`);
    }
  }
  return result;
}

/** The text of a fixture file for a list of events: one JSON object per line. */
export function fixtureText(events) {
  return `${events.map((event) => JSON.stringify(event)).join('\n')}\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const check = process.argv.includes('--check');
  let stale = false;
  for (const [name, events] of Object.entries(exampleEvents())) {
    const file = new URL(`${name}.events.jsonl`, FIXTURES);
    const text = fixtureText(events);
    if (check) {
      if (!existsSync(file) || readFileSync(file, 'utf8') !== text) {
        console.error(`out of date: ${fileURLToPath(file)}`);
        stale = true;
      }
    } else {
      writeFileSync(file, text);
      console.log(`wrote ${name}.events.jsonl (${events.length} events)`);
    }
  }
  if (stale) process.exitCode = 1;
}
