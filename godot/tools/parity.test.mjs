// Parity test: every case of the old JavaScript arena-rules tests has a counterpart in the GDScript tests.
//
// `test/fixtures/arena-rules-test-titles.json` is a fixed list of the 34 test titles of the JavaScript
// mockup. `godot/test/test_arena_rules.gd` ports them. Above each GDScript
// test, a comment `# JS: <exact title of the JavaScript test>` names its source.
// This test fails when a title has no counterpart, when a comment names a title that is not in the list,
// or when the order or the number differs. No case can be dropped without notice.
//
//   node --test tools/parity.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const TITLES_FILE = new URL('../test/fixtures/arena-rules-test-titles.json', import.meta.url);
const GD_FILE = new URL('../test/test_arena_rules.gd', import.meta.url);

/** The fixed list of the JavaScript test titles, in the order of the old file. */
export function frozenTitles() {
  return JSON.parse(readFileSync(TITLES_FILE, 'utf8')).titles;
}

/**
 * The titles of the `# JS: <title>` comments, in file order. Each comment must stand directly above a
 * `func test_` line. Returns the titles and the problems found.
 */
export function gdTitles(source) {
  const lines = source.split(/\r?\n/);
  const titles = [];
  const problems = [];
  lines.forEach((line, i) => {
    const match = /^# JS: (.*)$/.exec(line);
    if (!match) return;
    titles.push(match[1]);
    if (!/^func test_\w+\(/.test(lines[i + 1] ?? '')) problems.push(`line ${i + 1}: "# JS:" is not directly above a "func test_" line`);
  });
  const tests = lines.filter((line) => /^func test_\w+\(/.test(line)).length;
  if (tests !== titles.length) problems.push(`${tests} GDScript tests, but ${titles.length} "# JS:" comments`);
  return { titles, problems };
}

/** Compares the two lists. Returns the list of problems, empty when they agree. */
export function compareTitles(js, gd) {
  const problems = [];
  for (const title of js) if (!gd.includes(title)) problems.push(`no GDScript counterpart for the JavaScript test: ${title}`);
  for (const title of gd) if (!js.includes(title)) problems.push(`no JavaScript test with this title: ${title}`);
  const seen = new Set();
  for (const title of gd) {
    if (seen.has(title)) problems.push(`the title is used twice: ${title}`);
    seen.add(title);
  }
  if (problems.length === 0 && js.some((title, i) => title !== gd[i])) problems.push('the GDScript tests are not in the order of the JavaScript tests');
  return problems;
}

test('the fixed list holds the 34 titles', () => {
  const titles = frozenTitles();
  assert.equal(titles.length, 34, 'the old JavaScript file had 34 tests');
  assert.equal(new Set(titles).size, titles.length, 'no title is used twice');
});

test('every JavaScript test of arena-rules has a counterpart in test_arena_rules.gd', () => {
  const gd = gdTitles(readFileSync(GD_FILE, 'utf8'));
  assert.deepEqual(gd.problems, [], 'the "# JS:" comments are well placed');
  assert.deepEqual(compareTitles(frozenTitles(), gd.titles), []);
});

test('the parity check finds a missing, an extra and a misplaced title', () => {
  assert.deepEqual(compareTitles(['a', 'b'], ['a', 'b']), []);
  assert.equal(compareTitles(['a', 'b'], ['a']).length, 1, 'a missing title');
  assert.equal(compareTitles(['a'], ['a', 'x']).length, 1, 'an extra title');
  assert.equal(compareTitles(['a', 'b'], ['b', 'a']).length, 1, 'a changed order');
  assert.equal(compareTitles(['a', 'b'], ['a', 'b', 'b']).length, 1, 'a title used twice');
  const gd = gdTitles('# JS: a\nfunc test_a() -> void:\n\tpass\n\n# JS: b\n\nfunc test_b() -> void:\n\tpass\n');
  assert.equal(gd.problems.length, 1, 'a comment that is not directly above its test');
});
