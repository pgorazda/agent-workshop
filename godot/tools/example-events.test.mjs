// The GUT tests read test/fixtures/*.events.jsonl. This test checks that those files are still what the
// bridge adapters make from schema/examples/. If it fails, run:  node tools/example-events.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FIXTURES, exampleEvents, fixtureText } from './example-events.mjs';

const read = (file) => readFileSync(new URL(file, FIXTURES), 'utf8').replace(/\r\n/g, '\n');

for (const [name, events] of Object.entries(exampleEvents())) {
  test(`the fixture for the ${name} example is up to date`, () => {
    assert.equal(read(`${name}.events.jsonl`), fixtureText(events));
  });
}

test('each example gives a stream with tools, a failure and a finish', () => {
  for (const [name, events] of Object.entries(exampleEvents())) {
    const types = events.map((e) => e.type);
    assert.ok(types.includes('tool_start'), `${name}: tool_start`);
    assert.ok(events.some((e) => e.type === 'tool_end' && e.ok === false), `${name}: a failed tool`);
    assert.ok(types.includes('done') || types.includes('error'), `${name}: a finish`);
  }
});
