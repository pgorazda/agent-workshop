// Reads the log of a benchmark run of the client and prints how long the frames took in the long camera moves.
//
//   "$GODOT" --path godot -- --benchmark=ten --benchmark-out=run.csv        # needs a window (not --headless); writes run.csv
//                                                                           # and run.camera.json (the camera's moves)
//   node tools/benchmark-report.mjs run.csv                                 # prints the report
//   node tools/benchmark-report.mjs run.csv --json                          # the same numbers as JSON
//
// The CSV has one line for each frame: t (the time of the scene), frame_ms (the time since the frame before: it includes the wait
// for vsync), process_ms (the time of the client's own frame code) and move (the id of the camera move that is under way, 0 when
// the camera rests). The moves file has one entry for each move of the camera: { id, t, to, why, kind, apart, dur, peak, wide }.
// A long move is a fly or a scroll that widens the view to 4 rooms across or more (`wide`). A window is the run of frames with the
// id of one long move. docs/godot-client-plan.md ("Performance") says what is measured and what the pass rule is.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** A frame longer than this misses a frame of a 60 Hz screen. */
export const FRAME_LIMIT_MS = 16.7;
/** The pass rule of the plan (a proposal): in a long move at most 1% of the frames over 20 ms, none over 33 ms, and the 99th percentile of the process time at most 8 ms. */
export const RULE = { slow_ms: 20, share: 0.01, worst_ms: 33, process_p99_ms: 8 };

/** The CSV text of a run as a list of frames: [{ t, frame_ms, process_ms, move }]. */
export function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim() !== '');
  const header = lines.shift()?.split(',') ?? [];
  const expected = ['t', 'frame_ms', 'process_ms', 'move'];
  if (header.join(',') !== expected.join(',')) throw new Error(`the header of the CSV must be ${expected.join(',')}, it is ${header.join(',')}`);
  return lines.map((line, index) => {
    const parts = line.split(',').map(Number);
    if (parts.length !== 4 || parts.some((value) => !Number.isFinite(value))) throw new Error(`line ${index + 2} of the CSV is not four numbers: ${line}`);
    return { t: parts[0], frame_ms: parts[1], process_ms: parts[2], move: parts[3] };
  });
}

/** The p-th percentile (0 to 100) of a list of numbers: the nearest rank. NaN for an empty list. */
export function percentile(values, p) {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const rank = Math.max(1, Math.ceil((p / 100) * sorted.length));
  return sorted[rank - 1];
}

/** Count, median, 95th and 99th percentile, worst, and the share over `limit` ms, for a list of frame times. */
export function stats(values, limit = FRAME_LIMIT_MS) {
  const over = values.filter((value) => value > limit).length;
  return {
    frames: values.length,
    median: percentile(values, 50),
    p95: percentile(values, 95),
    p99: percentile(values, 99),
    worst: values.length ? Math.max(...values) : NaN,
    over_share: values.length ? over / values.length : NaN,
  };
}

/** The long moves of the camera: flies and scrolls that widen the view to 4 rooms across or more. */
export function longMoves(moves) {
  return moves.filter((move) => (move.kind === 'fly' || move.kind === 'scroll') && move.wide);
}

/**
 * The report: for each long move the stats of its frames, the stats of all of them together, and the stats of the whole scene.
 * Frames before time 0 are not part of the scene (they are the agents that were there before it, if the run counted them).
 */
export function report(frames, moves, limit = FRAME_LIMIT_MS) {
  const scene = frames.filter((frame) => frame.t >= 0);
  const windows = longMoves(moves).map((move) => {
    const inside = scene.filter((frame) => frame.move === move.id);
    return {
      id: move.id, t: move.t, to: move.to, why: move.why, kind: move.kind, dur: move.dur, peak: move.peak,
      frame_ms: stats(inside.map((frame) => frame.frame_ms), limit),
      process_ms: stats(inside.map((frame) => frame.process_ms), limit),
      slow_share: inside.length ? inside.filter((frame) => frame.frame_ms > RULE.slow_ms).length / inside.length : NaN,
    };
  });
  const pooled = scene.filter((frame) => windows.some((window) => window.id === frame.move));
  return {
    limit_ms: limit,
    long_moves: windows.length,
    windows,
    all_windows: { frame_ms: stats(pooled.map((frame) => frame.frame_ms), limit), process_ms: stats(pooled.map((frame) => frame.process_ms), limit) },
    scene: { frame_ms: stats(scene.map((frame) => frame.frame_ms), limit), process_ms: stats(scene.map((frame) => frame.process_ms), limit) },
    rule: passRule(windows),
  };
}

/** Checks the pass rule of the plan on each window. A window with no frame fails. */
export function passRule(windows) {
  const failures = [];
  for (const window of windows) {
    const where = `move ${window.id} (${window.kind} to ${window.to})`;
    if (window.frame_ms.frames === 0) failures.push(`${where}: no frames`);
    if (window.slow_share > RULE.share) failures.push(`${where}: ${(window.slow_share * 100).toFixed(1)}% of the frames are over ${RULE.slow_ms} ms`);
    if (window.frame_ms.worst > RULE.worst_ms) failures.push(`${where}: the worst frame is ${window.frame_ms.worst.toFixed(1)} ms (limit ${RULE.worst_ms})`);
    if (window.process_ms.p99 > RULE.process_p99_ms) failures.push(`${where}: the 99th percentile of the process time is ${window.process_ms.p99.toFixed(2)} ms (limit ${RULE.process_p99_ms})`);
  }
  return { pass: windows.length > 0 && failures.length === 0, failures };
}

const ms = (value) => (Number.isFinite(value) ? value.toFixed(2) : '-');
const pct = (value) => (Number.isFinite(value) ? `${(value * 100).toFixed(1)}%` : '-');

/** The report as text. */
export function format(result) {
  const lines = [];
  const row = (label, s) => `${label.padEnd(28)} ${String(s.frames).padStart(6)} ${ms(s.median).padStart(8)} ${ms(s.p95).padStart(8)} ${ms(s.p99).padStart(8)} ${ms(s.worst).padStart(8)} ${pct(s.over_share).padStart(8)}`;
  lines.push(`frame time in ms (share is of the frames over ${result.limit_ms} ms)`);
  lines.push(`${'window'.padEnd(28)} ${'frames'.padStart(6)} ${'median'.padStart(8)} ${'p95'.padStart(8)} ${'p99'.padStart(8)} ${'worst'.padStart(8)} ${'>limit'.padStart(8)}`);
  for (const window of result.windows) {
    lines.push(row(`#${window.id} ${window.kind} to ${window.to} at ${window.t.toFixed(1)} s`, window.frame_ms));
  }
  lines.push(row(`all ${result.long_moves} long moves`, result.all_windows.frame_ms));
  lines.push(row('the whole scene', result.scene.frame_ms));
  lines.push('');
  lines.push('process time of the client code in ms (not the drawing of the engine)');
  lines.push(row(`all ${result.long_moves} long moves`, result.all_windows.process_ms));
  lines.push(row('the whole scene', result.scene.process_ms));
  lines.push('');
  lines.push(result.rule.pass ? 'pass rule of the plan: met on this machine' : `pass rule of the plan: NOT met${result.long_moves === 0 ? ' (no long move in the log)' : ''}`);
  for (const failure of result.rule.failures) lines.push(`  ${failure}`);
  return lines.join('\n') + '\n';
}

/** The moves file that belongs to a CSV: `run.csv` has `run.camera.json`. */
export function movesPathOf(csvPath) {
  return csvPath.replace(/\.[^./\\]+$/, '') + '.camera.json';
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const path = args.find((arg) => !arg.startsWith('--'));
  if (!path) {
    console.error('usage: node tools/benchmark-report.mjs <run.csv> [--json]');
    process.exit(2);
  }
  const frames = parseCsv(readFileSync(path, 'utf8'));
  const moves = JSON.parse(readFileSync(movesPathOf(path), 'utf8'));
  const result = report(frames, moves);
  process.stdout.write(args.includes('--json') ? JSON.stringify(result, null, 2) + '\n' : format(result));
}
