// Checks the GDScript files of the project. Warnings count as errors.
//
//   node tools/check.mjs
//
// Godot prints warnings only in a debug run (-d), and `--check-only` does not make them fatal.
// So this script loads every script in one debug run, reads the output and fails on any
// "WARNING", "ERROR" or "SCRIPT ERROR" line. The addons are not checked.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';
import { importProject } from './run-gut.mjs';

export function checkScripts(godot = resolveGodot()) {
  importProject(godot);
  const run = spawnSync(godot, ['--headless', '-d', '--path', GODOT_DIR, '-s', 'res://tools/check_scripts.gd'], {
    encoding: 'utf8',
  });
  const output = `${run.stdout ?? ''}${run.stderr ?? ''}`;
  const problems = output.split(/\r?\n/).filter((line) => /^(WARNING|ERROR|SCRIPT ERROR|FAILED TO LOAD)/.test(line));
  return { status: run.status, output, problems };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { status, output, problems } = checkScripts();
  if (status !== 0 || problems.length > 0 || !/CHECKED \d+ scripts/.test(output)) {
    console.error(output);
    console.error(`check failed: ${problems.length} problem line(s), exit code ${status}`);
    process.exitCode = 1;
  } else {
    console.log(output.match(/CHECKED \d+ scripts/)[0] + ': no warnings, no errors');
  }
}
