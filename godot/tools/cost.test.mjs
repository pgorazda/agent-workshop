// The numbers of the tools that measure the start-up and the cost of the client. The tests use made-up readings: they start
// no client and need no window.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpuPercent, memoryMb, SCENARIOS, STATES, stateHolds } from './cost.mjs';
import { median, summarize, summarizeRun, windowBuild } from './startup.mjs';

test('the CPU is the process time over the wall time, in percent of one core', () => {
  const samples = [
    { t: 0, cpuMs: 0 },
    { t: 1000, cpuMs: 100 },
    { t: 2000, cpuMs: 300 },
    { t: 3000, cpuMs: 400 },
  ];
  const cpu = cpuPercent(samples);
  assert.equal(cpu.mean, (400 / 3000) * 100);
  assert.equal(cpu.peak, 20);
  assert.deepEqual(cpu.second_by_second, [10, 20, 10]);
});

test('a core that is used all the time is 100 percent, and two cores are 200', () => {
  assert.equal(cpuPercent([{ t: 0, cpuMs: 0 }, { t: 1000, cpuMs: 1000 }]).mean, 100);
  assert.equal(cpuPercent([{ t: 0, cpuMs: 0 }, { t: 1000, cpuMs: 2000 }]).mean, 200);
});

test('one reading gives no CPU number', () => {
  assert.ok(Number.isNaN(cpuPercent([{ t: 0, cpuMs: 5 }]).mean));
});

test('the memory is the mean and the peak in megabytes', () => {
  const mb = 1024 * 1024;
  const memory = memoryMb([{ memBytes: 100 * mb }, { memBytes: 200 * mb }, { memBytes: 150 * mb }]);
  assert.equal(memory.mean, 150);
  assert.equal(memory.peak, 200);
});

test('the scenarios and the states are the ones that the cost tool knows', () => {
  assert.deepEqual(STATES, ['focus', 'unfocused', 'minimized']);
  assert.ok(SCENARIOS.includes('idle') && SCENARIOS.includes('replay') && SCENARIOS.includes('ten'));
});

test('the median of a list', () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 2, 3]), 2.5);
  assert.ok(Number.isNaN(median([])));
});

test('a run of the start-up: the time from the start of the process and the parts', () => {
  const report = {
    marks_ms: { ready_begin: 2000, atlas_loaded: 2040, ready_end: 2200, first_process: 2210, first_draw: 2230 },
    frame_ms: [4, 3, 3],
    unix_ms_at_first_draw: 1_000_000 + 2500,
  };
  const run = summarizeRun(report, 1_000_000);
  assert.equal(run.process_to_first_frame, 2500);
  assert.equal(run.engine_to_ready, 2000);
  assert.equal(run.atlases, 40);
  assert.equal(run.ready, 200);
  assert.equal(run.first_process_after_ready, 10);
  assert.equal(run.first_frame_after_ready, 30);
});

test('the start-up of several runs is the medians', () => {
  const run = (total) => ({ process_to_first_frame: total, engine_to_ready: 2000, atlases: 40, ready: 200, first_process_after_ready: 10, first_frame_after_ready: 30, frame_ms: [4, 3, 3] });
  const summary = summarize([run(2400), run(2600), run(3500)]);
  assert.equal(summary.runs, 3);
  assert.equal(summary.process_to_first_frame, 2600);
  assert.equal(summary.process_to_first_frame_min, 2400);
  assert.equal(summary.process_to_first_frame_max, 3500);
  assert.equal(summary.frame_ms_first, 4);
  assert.equal(summary.frame_ms_later, 3);
});

test('the window build is the console build without "_console", when the file is there', () => {
  assert.equal(windowBuild('/nowhere/Godot_v4.7.2-stable_win64_console.exe'), '/nowhere/Godot_v4.7.2-stable_win64_console.exe', 'no such file: the path stays');
  assert.equal(windowBuild('/a/b/godot'), '/a/b/godot');
});

test('the state of the window is checked against the lines that the client wrote', () => {
  const none = [];
  assert.equal(stateHolds('focus', none), true, 'a window that starts with the focus says nothing');
  assert.equal(stateHolds('unfocused', none), false);
  assert.equal(stateHolds('minimized', none), false);
  assert.equal(stateHolds('unfocused', ['[live] focus true', '[live] focus false']), true);
  assert.equal(stateHolds('focus', ['[live] focus true', '[live] focus false']), false);
  assert.equal(stateHolds('focus', ['[live] focus false', '[live] focus true']), true);
  assert.equal(stateHolds('minimized', ['[live] focus false', '[live] minimized true']), true);
  assert.equal(stateHolds('unfocused', ['[live] focus false', '[live] minimized true']), false, 'minimized is not just unfocused');
  assert.equal(stateHolds('focus', ['[live] minimized true', '[live] minimized false', '[live] focus true']), true);
});
