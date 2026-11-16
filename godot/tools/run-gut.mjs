// Runs the GUT tests headless.
//
//   node tools/run-gut.mjs                 all tests in godot/test/
//   node tools/run-gut.mjs -gselect=event  only the test files with "event" in their name
//
// Extra arguments go to GUT. Set GODOT to the editor (see README.md).
//
// GUT does not fail when a test script cannot be used: a script with a parse error is skipped with a warning
// ("Ignoring script ... because it does not extend GutTest"), and the run still ends with "All tests passed". So this
// tool reads the output and fails when
//   * GUT ignored a script, or Godot printed a script or parse error;
//   * a run of all tests (no GUT filter in the arguments) ran fewer scripts than there are test_*.gd files in test/.

import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';

/** Godot must import the project once. Then the global class names and the .uid files exist. */
export function importProject(godot) {
  const run = spawnSync(godot, ['--headless', '--path', GODOT_DIR, '--import'], { encoding: 'utf8' });
  if (run.status !== 0) throw new Error(`Godot import failed (exit ${run.status}):\n${run.stdout}\n${run.stderr}`);
}

/** The test scripts that GUT should run: every file test_*.gd under a folder, at any depth. */
export function countTestFiles(folder = join(GODOT_DIR, 'test')) {
  let count = 0;
  for (const entry of readdirSync(folder, { withFileTypes: true })) {
    if (entry.isDirectory()) count += countTestFiles(join(folder, entry.name));
    else if (/^test_.*\.gd$/.test(entry.name)) count += 1;
  }
  return count;
}

const ANSI = /\u001b\[[0-9;]*m/g;

/** True when the arguments choose some of the tests (a filter), so that fewer scripts are expected. */
export function hasFilter(args) {
  return args.some((arg) => /^-g(select|test|dir|unit_test_name|include_subdirs)\b/.test(arg) || /^-g(select|test|dir)=/.test(arg));
}

/**
 * Looks for what GUT does not turn into a failure. Returns a list of problems (empty when the output is fine).
 * `expectedScripts` is the number of test files, or null when a filter is on.
 */
export function problemsInOutput(output, expectedScripts) {
  const text = output.replace(ANSI, '');
  const problems = [];
  for (const line of text.split(/\r?\n/)) {
    if (/Ignoring script/.test(line)) problems.push(`GUT ignored a script: ${line.trim()}`);
    else if (/^(SCRIPT ERROR|ERROR: .*(Parse Error|Failed to load script))/.test(line) || /Parse Error/.test(line)) problems.push(`Godot reported an error: ${line.trim()}`);
  }
  const ran = /^Scripts\s+(\d+)/m.exec(text);
  if (!ran) problems.push('the summary of GUT has no "Scripts" line: the run did not finish');
  else if (expectedScripts !== null && Number(ran[1]) < expectedScripts) {
    problems.push(`GUT ran ${ran[1]} scripts, but there are ${expectedScripts} test_*.gd files`);
  }
  return problems;
}

export function runGut(args = [], godot = resolveGodot()) {
  importProject(godot);
  const run = spawnSync(
    godot,
    ['--headless', '--path', GODOT_DIR, '-s', 'res://addons/gut/gut_cmdln.gd', '-gconfig=res://.gutconfig.json', ...args],
    { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 },
  );
  process.stdout.write(run.stdout ?? '');
  process.stderr.write(run.stderr ?? '');
  const problems = problemsInOutput(`${run.stdout ?? ''}\n${run.stderr ?? ''}`, hasFilter(args) ? null : countTestFiles());
  for (const problem of problems) console.error(`error: ${problem}`);
  return { status: problems.length > 0 && (run.status ?? 1) === 0 ? 1 : (run.status ?? 1), problems };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const result = runGut(process.argv.slice(2));
    process.exitCode = result.status;
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exitCode = 1;
  }
}
