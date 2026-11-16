// Tests of the benchmark report: the CSV, the percentiles, and the windows of long moves.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { FRAME_LIMIT_MS, RULE, format, longMoves, movesPathOf, parseCsv, passRule, percentile, report, stats } from './benchmark-report.mjs';

test('percentile uses the nearest rank', () => {
  const values = Array.from({ length: 100 }, (_, i) => i + 1);
  assert.equal(percentile(values, 50), 50);
  assert.equal(percentile(values, 95), 95);
  assert.equal(percentile(values, 99), 99);
  assert.equal(percentile(values, 100), 100);
  assert.equal(percentile([5], 99), 5);
  assert.equal(percentile([3, 1, 2], 50), 2);
  assert.ok(Number.isNaN(percentile([], 50)));
});

test('stats: count, median, percentiles, worst and the share over the limit', () => {
  const values = [10, 10, 10, 10, 10, 10, 10, 10, 20, 40];
  const s = stats(values);
  assert.equal(s.frames, 10);
  assert.equal(s.median, 10);
  assert.equal(s.p95, 40);
  assert.equal(s.worst, 40);
  assert.equal(s.over_share, 0.2);
  assert.equal(stats([16.7]).over_share, 0, 'a frame of exactly the limit is not over it');
  assert.equal(FRAME_LIMIT_MS, 16.7);
});

test('parseCsv reads the lines and refuses a wrong header or a bad line', () => {
  const frames = parseCsv('t,frame_ms,process_ms,move\n0.0167,16.700,0.800,0\n0.0333,17.100,0.900,3\n');
  assert.deepEqual(frames, [{ t: 0.0167, frame_ms: 16.7, process_ms: 0.8, move: 0 }, { t: 0.0333, frame_ms: 17.1, process_ms: 0.9, move: 3 }]);
  assert.throws(() => parseCsv('a,b,c,d\n1,2,3,4\n'), /header/);
  assert.throws(() => parseCsv('t,frame_ms,process_ms,move\n1,2,x,4\n'), /line 2/);
});

test('long moves are the flies and scrolls that widen the view to 4 rooms or more', () => {
  const moves = [
    { id: 1, kind: 'slide', wide: false }, { id: 2, kind: 'fly', wide: true }, { id: 3, kind: 'fly', wide: false },
    { id: 4, kind: 'scroll', wide: true }, { id: 5, kind: 'zoom', wide: false }, { id: 6, kind: 'cut', wide: false },
  ];
  assert.deepEqual(longMoves(moves).map((move) => move.id), [2, 4]);
});

function makeRun() {
  const frames = [];
  const moves = [
    { id: 1, t: 1, to: 'B', why: 'click', kind: 'slide', dur: 0.5, peak: 0, wide: false },
    { id: 2, t: 2, to: 'Z', why: 'pull:approval', kind: 'fly', dur: 1, peak: 8, wide: true },
    { id: 3, t: 5, to: 'page 2', why: 'key', kind: 'scroll', dur: 0.8, peak: 8, wide: true },
  ];
  for (let i = 0; i < 600; i++) {
    const t = i / 60;
    const move = t >= 2 && t < 3 ? 2 : t >= 5 && t < 5.8 ? 3 : t >= 1 && t < 1.5 ? 1 : 0;
    // a long move costs more: 6 ms for the frames of the first window, with one slow frame in the second
    const frame_ms = move === 2 ? 16.7 : move === 3 ? (i === 320 ? 25 : 16.7) : 16.6;
    frames.push({ t, frame_ms, process_ms: move ? 2 : 1, move });
  }
  frames.push({ t: -1, frame_ms: 500, process_ms: 400, move: 0 });
  return { frames, moves };
}

test('report: the windows, the pooled windows and the whole scene (frames before time 0 do not count)', () => {
  const { frames, moves } = makeRun();
  const result = report(frames, moves);
  assert.equal(result.long_moves, 2);
  assert.deepEqual(result.windows.map((window) => window.id), [2, 3]);
  assert.equal(result.windows[0].frame_ms.frames, 60);
  assert.equal(result.windows[1].frame_ms.frames, 48);
  assert.equal(result.windows[1].frame_ms.worst, 25);
  assert.equal(result.all_windows.frame_ms.frames, 108);
  assert.equal(result.scene.frame_ms.frames, 600, 'the frame before time 0 is left out');
  assert.equal(result.scene.frame_ms.worst, 25);
  assert.equal(result.windows[0].frame_ms.over_share, 0, 'a frame of exactly 16.7 ms is not over the limit');
});

test('the pass rule: one slow frame in 48 is over 1%, and a worst frame over 33 ms fails', () => {
  const { frames, moves } = makeRun();
  const result = report(frames, moves);
  assert.equal(result.rule.pass, false);
  assert.match(result.rule.failures[0], /move 3/);
  const calm = report(frames.map((frame) => ({ ...frame, frame_ms: Math.min(frame.frame_ms, 16.7) })), moves);
  assert.equal(calm.rule.pass, true);
  assert.equal(passRule([]).pass, false, 'no long move: nothing was measured');
  const hard = report(frames.map((frame, i) => (i === 130 && frame.move === 2 ? { ...frame, frame_ms: 40 } : frame)), moves);
  assert.ok(hard.rule.failures.some((text) => /worst frame is 40/.test(text)));
  assert.equal(RULE.worst_ms, 33);
});

test('the text report lists each window and the scene', () => {
  const { frames, moves } = makeRun();
  const text = format(report(frames, moves));
  assert.match(text, /#2 fly to Z at 2\.0 s/);
  assert.match(text, /#3 scroll to page 2 at 5\.0 s/);
  assert.match(text, /all 2 long moves/);
  assert.match(text, /the whole scene/);
  assert.match(text, /pass rule of the plan: NOT met/);
});

test('the moves file of a CSV', () => {
  assert.equal(movesPathOf('run.csv'), 'run.camera.json');
  assert.equal(movesPathOf('a/b.c/run-1.csv'), 'a/b.c/run-1.camera.json');
});
