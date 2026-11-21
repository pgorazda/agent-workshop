// Measures the start-up of the Godot client: the time from the start of the process to the first frame of the room, and the parts
// of it. It starts the client several times with `--startup-report=<file>`. The client writes the times of its engine
// clock and the time of the system clock at its first drawn frame, and quits. This tool adds the time at which it started the process.
//
//   node tools/startup.mjs                       # five runs of the scene `multi`
//   node tools/startup.mjs --runs 9 --scene ten  # nine runs of another scene
//   node tools/startup.mjs --json                # the numbers as JSON
//   node tools/startup.mjs --app <path to an exported app>   # a release export
//
// It needs a window (not --headless) and the Godot editor (see godot/README.md). On Windows it uses the window build of the editor
// when it finds one next to the console build, so that no console wrapper adds a process. The runs are warm: the files of the project
// are in the cache of the system, and so is the cache of the graphics driver. A cold start was not measured.

import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';

/** The median of a list of numbers (NaN for an empty list). */
export function median(values) {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * One run as numbers, in milliseconds. `report` is what the client wrote, `spawnedAtMs` the system time at which the process was started.
 * - process_to_first_frame: from the start of the process to the first drawn frame of the room (the number that the budget is about);
 * - engine_to_ready: from the start of the engine to the start of the first scene's `_ready` (engine, project, and the scripts that the scene needs);
 * - atlases: the time to load the picture files;
 * - ready: the `_ready` of the view (atlases, nodes, the first scene state);
 * - first_frame_after_ready: from the end of `_ready` to the first drawn frame (what the engine does for the first picture);
 * - frame_ms: the time between the drawn frames after the first (a list).
 */
export function summarizeRun(report, spawnedAtMs) {
  const m = report.marks_ms;
  return {
    process_to_first_frame: report.unix_ms_at_first_draw - spawnedAtMs,
    engine_to_ready: m.ready_begin,
    atlases: m.atlas_loaded - m.ready_begin,
    ready: m.ready_end - m.ready_begin,
    first_process_after_ready: m.first_process - m.ready_end,
    first_frame_after_ready: m.first_draw - m.ready_end,
    frame_ms: report.frame_ms,
  };
}

/** The medians of several runs: { process_to_first_frame, engine_to_ready, ..., frame_ms_first, frame_ms_later }. */
export function summarize(runs) {
  const pick = (key) => median(runs.map((run) => run[key]));
  return {
    runs: runs.length,
    process_to_first_frame: pick('process_to_first_frame'),
    process_to_first_frame_min: Math.min(...runs.map((run) => run.process_to_first_frame)),
    process_to_first_frame_max: Math.max(...runs.map((run) => run.process_to_first_frame)),
    engine_to_ready: pick('engine_to_ready'),
    atlases: pick('atlases'),
    ready: pick('ready'),
    first_process_after_ready: pick('first_process_after_ready'),
    first_frame_after_ready: pick('first_frame_after_ready'),
    frame_ms_first: median(runs.map((run) => run.frame_ms[0])),
    frame_ms_later: median(runs.flatMap((run) => run.frame_ms.slice(1))),
  };
}

/** The window build of the editor when the path is the console build and the window build lies next to it. */
export function windowBuild(path) {
  const candidate = path.replace(/_console(\.exe)$/, '$1');
  return candidate !== path && existsSync(candidate) ? candidate : path;
}

function runOnce(godot, scene, workDir, app = false) {
  const file = join(workDir, `report-${Date.now()}.json`);
  const args = [...(app ? [] : ['--path', GODOT_DIR]), '--', `--demo=${scene}`, `--startup-report=${file}`];
  return new Promise((resolve, reject) => {
    const spawnedAtMs = Date.now();
    const child = spawn(godot, args, { stdio: 'ignore' });
    const timer = setTimeout(() => child.kill(), 60000);
    child.on('error', reject);
    child.on('exit', () => {
      clearTimeout(timer);
      if (!existsSync(file)) return reject(new Error('the client wrote no report (does the machine have a display?)'));
      resolve(summarizeRun(JSON.parse(readFileSync(file, 'utf8')), spawnedAtMs));
    });
  });
}

async function main() {
  const args = process.argv.slice(2);
  const option = (name, fallback) => (args.includes(name) ? args[args.indexOf(name) + 1] : fallback);
  const runs = Number(option('--runs', 5));
  const scene = option('--scene', 'multi');
  const app = option('--app', '');
  const godot = app || windowBuild(resolveGodot());
  const workDir = mkdtempSync(join(tmpdir(), 'agent-workshop-startup-'));
  const results = [];
  try {
    await runOnce(godot, scene, workDir, Boolean(app)); // the first run loads the files into the cache of the system: it is not counted
    for (let i = 0; i < runs; i += 1) results.push(await runOnce(godot, scene, workDir, Boolean(app)));
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
  const summary = summarize(results);
  if (args.includes('--json')) {
    console.log(JSON.stringify({ scene, ...summary, runs_detail: results }, null, 2));
    return;
  }
  const f = (value) => value.toFixed(0).padStart(6);
  console.log(`start-up of the scene ${scene}, ${summary.runs} warm runs (the first run is left out); milliseconds, medians`);
  console.log(`${f(summary.process_to_first_frame)}  from the start of the process to the first frame of the room (runs: ${summary.process_to_first_frame_min.toFixed(0)} to ${summary.process_to_first_frame_max.toFixed(0)})`);
  console.log(`${f(summary.engine_to_ready)}  engine start to the start of the view's _ready (engine, project, scripts)`);
  console.log(`${f(summary.atlases)}  the picture files (atlases)`);
  console.log(`${f(summary.ready)}  the _ready of the view, with the atlases`);
  console.log(`${f(summary.first_frame_after_ready)}  from the end of _ready to the first drawn frame`);
  console.log(`${f(summary.frame_ms_first)}  the second frame, after the first`);
  console.log(`${f(summary.frame_ms_later)}  the frames after that`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
