// Tests of the level tool (phase G-7), without a browser and without Godot:  node --test
//
// They check the search for the worst start time on small made-up signals, that the numbers of the tool are the numbers of the player,
// and the levels of the real files in art/sound/.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { EVENTS, GODOT, LIMITER_CEILING_DB, MUSIC_VOLUME_DB, TUNES, analyse, loadSound, mixLevels, peakAt, toDb } from './sound-levels.mjs';

const PLAYER = readFileSync(join(GODOT, 'src', 'view', 'sound_player.gd'), 'utf8');
const MODEL = readFileSync(join(GODOT, 'src', 'core', 'sound_model.gd'), 'utf8');

test('the numbers of the tool are those of the player', () => {
  const number = (name) => Number(new RegExp(`^const ${name} := (-?[0-9.]+)`, 'm').exec(PLAYER)[1]);
  assert.equal(number('MUSIC_VOLUME_DB'), MUSIC_VOLUME_DB);
  assert.equal(number('LIMITER_CEILING_DB'), LIMITER_CEILING_DB);
});

test('the names of the tool are the names of the model, and each has a file', () => {
  const tunes = [...MODEL.matchAll(/"name": "(\w+)"/g)].map((m) => m[1]);
  assert.deepEqual(tunes, TUNES);
  const events = /const EVENT_SOUNDS: Array\[String\] = \[(.*)\]/.exec(MODEL)[1].match(/"(\w+)"/g).map((s) => s.slice(1, -1));
  assert.deepEqual(events, EVENTS);
  for (const name of [...TUNES, ...EVENTS]) assert.ok(loadSound(name).length > 0, name);
});

test('peakAt adds the event to the tune at the start time and lets the tune wrap round', () => {
  const tune = Int16Array.from([100, 200, 300, 400]);
  const event = Int16Array.from([10, -1000, 10]);
  assert.equal(peakAt(tune, event, 0), 800, '200 - 1000 is -800');
  assert.equal(peakAt(tune, event, 3), 900, 'it wraps: 400+10, then 100-1000, then 200+10');
});

test('mixLevels finds the worst start time, with the search by blocks and with a plain search', () => {
  // a tune that is quiet except for one burst; an event with one peak
  const tune = new Int16Array(64 * 40);
  for (let i = 64 * 25 + 10; i < 64 * 25 + 14; i++) tune[i] = 20000;
  const event = new Int16Array(64 * 3);
  event[64 + 5] = 15000;
  const result = mixLevels(tune, event, 64, 0);
  assert.equal(result.worst, 35000, 'the two peaks meet');
  assert.equal(result.worstAt, 64 * 25 + 10 - (64 + 5), 'at this start time');
  const brute = Math.max(...Array.from({ length: tune.length }, (_, o) => peakAt(tune, event, o)));
  assert.equal(result.worst, brute, 'the plain search over every start time gives the same peak');
  const every = mixLevels(tune, event, 1, 0);
  assert.equal(every.share0, 4 / tune.length, 'four start times of all of them are above full scale (one for each sample of the burst)');
  assert.equal(result.share0, 0, 'a coarse list of start times misses them: the search by blocks is what finds the worst one');
});

test('the tune volume is applied before the sum', () => {
  const tune = Int16Array.from([20000, 20000, 20000, 20000]);
  const event = Int16Array.from([10000]);
  assert.ok(Math.abs(mixLevels(tune, event, 1, 0).worst - 30000) < 1e-6);
  assert.ok(Math.abs(mixLevels(tune, event, 1, -6.0206).worst - 20000) < 5);
});

test('the real files: a tune and an event sound can add up above full scale, but not far, and the limiter ceiling is below full scale', () => {
  const rows = analyse(4096);
  assert.equal(rows.length, TUNES.length * EVENTS.length);
  const worst = rows.reduce((a, b) => (b.worstDb > a.worstDb ? b : a));
  assert.ok(worst.worstDb > 0, 'the sum goes above full scale in the worst case: the master limiter is needed');
  assert.ok(worst.worstDb < 6, `the worst sum is ${worst.worstDb.toFixed(1)} dBFS: below the double of full scale, so the limiter takes at most 6 dB off`);
  assert.ok(LIMITER_CEILING_DB < 0);
  for (const row of rows) {
    assert.ok(row.worstDb <= row.sumOfPeaksDb + 1e-6, `${row.tune} + ${row.event}: the real worst case is not above the sum of the peaks`);
    assert.ok(row.shareOverFull <= row.shareOverCeiling, 'the share over full scale is part of the share over the ceiling');
  }
  // an event sound alone never reaches full scale, and neither does a tune
  assert.ok(toDb(32767) < 0);
});
