// Tests of the checks that run-gut.mjs makes on the output of GUT. They need no Godot.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { countTestFiles, hasFilter, problemsInOutput } from './run-gut.mjs';

const GOOD = 'Run Summary\n\nTotals\n------\nScripts              28\nTests               285\nPassing Tests       285\n---- All tests passed! ----\n';

test('a good run has no problem', () => {
  assert.deepEqual(problemsInOutput(GOOD, 28), []);
  assert.deepEqual(problemsInOutput(GOOD, null), []);
});

test('a script that GUT ignores is a problem', () => {
  const output = `[WARNING]: Ignoring script res://test/test_x.gd because it does not extend GutTest\n${GOOD}`;
  const problems = problemsInOutput(output, 28);
  assert.equal(problems.length, 1);
  assert.match(problems[0], /ignored a script/);
});

test('a parse error is a problem', () => {
  const output = `SCRIPT ERROR: Parse Error: Unexpected identifier\n   at: GDScript::reload (res://test/test_x.gd:3)\n${GOOD}`;
  assert.ok(problemsInOutput(output, null).length >= 1);
});

test('fewer scripts than test files is a problem, unless a filter is on', () => {
  const problems = problemsInOutput(GOOD, 29);
  assert.equal(problems.length, 1);
  assert.match(problems[0], /ran 28 scripts, but there are 29/);
  assert.deepEqual(problemsInOutput(GOOD, null), []);
});

test('a run with no summary is a problem', () => {
  assert.equal(problemsInOutput('nothing', 3).length, 1);
});

test('colour codes do not hide the lines', () => {
  const output = `\u001b[33m[WARNING]: Ignoring script a.gd\u001b[0m\n\u001b[1mScripts              28\u001b[0m\n`;
  assert.equal(problemsInOutput(output, 28).length, 1);
});

test('a filter in the arguments is found', () => {
  assert.equal(hasFilter(['-gselect=event']), true);
  assert.equal(hasFilter(['-gtest=res://test/test_a.gd']), true);
  assert.equal(hasFilter([]), false);
  assert.equal(hasFilter(['-glog=2']), false);
});

test('the test files of this project are counted', () => {
  assert.ok(countTestFiles() >= 28);
});
