// Tests of the sound render tool, without a browser:  node --test
//
// They check the helpers of render-sound.mjs, the numbers of the tool against sound.js, and the files in art/sound/.
// The render itself needs Chromium. Run `node tools/render-sound.mjs --check` for it (see README.md).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DEFAULT_RATE,
  EFFECTS,
  INTRO_BARS,
  MELODY_BARS,
  RENDER_QUANTUM,
  TUNE_PASSES,
  assertNoShorterLoop,
  checkLevels,
  cutLoop,
  levels,
  loopRate,
  makeWav,
  parseWav,
  updateManifest,
} from './render-sound.mjs';

const GODOT = fileURLToPath(new URL('..', import.meta.url));
const SOUND_DIR = join(GODOT, 'art', 'sound');

/** Loads sound.js in Node with fake globals and exposes the internal tune table (the file itself stays as it is). */
function loadTunes() {
  const source = readFileSync(join(GODOT, 'art', 'sound_src', 'sound.js'), 'utf8').replace('window.SoundArt = {', 'window.SoundArt = { __TUNES: TUNES,');
  const window = {};
  runInNewContext(source, { window, mulberry32: () => () => 0 }); // the file is part of this repository
  return window.SoundArt.__TUNES;
}

test('the tool numbers (bars, intro, passes) match sound.js', () => {
  const tunes = loadTunes();
  assert.deepEqual(Object.keys(tunes).sort(), Object.keys(MELODY_BARS).sort());
  for (const [name, tune] of Object.entries(tunes)) {
    assert.equal(tune.melody.length, MELODY_BARS[name], `${name}: bars of the melody`);
    assert.equal(tune.chords.length, MELODY_BARS[name], `${name}: one chord entry for each bar`);
    assert.equal(tune.intro, INTRO_BARS[name], `${name}: intro bars`);
    // The lead repeats after TUNE_PASSES passes, and not after fewer.
    const sig = (round) => JSON.stringify(tune.lead(round));
    for (let round = 0; round < 8; round++) assert.equal(sig(round), sig(round + TUNE_PASSES), `${name}: lead(${round}) equals lead(${round + TUNE_PASSES})`);
    for (let passes = 1; passes < TUNE_PASSES; passes++) assert.notEqual(sig(0), sig(passes), `${name}: the lead changes after ${passes} pass(es)`);
  }
});

test('the event sounds of the tool are the ones of sound.js', () => {
  const source = readFileSync(join(GODOT, 'art', 'sound_src', 'sound.js'), 'utf8');
  const block = /const EFFECTS = \{([\s\S]*?)\n\};/.exec(source)[1];
  const names = [...block.matchAll(/^  (\w+): \(ctx, out, at\)/gm)].map((m) => m[1]);
  assert.deepEqual(names.sort(), Object.keys(EFFECTS).sort());
});

test('a loop rate puts the loop on a whole number of render blocks, and stays close to the nominal rate', () => {
  const tunes = loadTunes();
  for (const nominal of [22050, 44100]) {
    for (const [name, tune] of Object.entries(tunes)) {
      const bar = (60 / tune.bpm) * tune.beats;
      const seconds = MELODY_BARS[name] * TUNE_PASSES * bar;
      const rate = loopRate(seconds, nominal);
      const samples = seconds * rate;
      assert.ok(Math.abs(samples - Math.round(samples)) < 1e-6, `${name}: whole samples`);
      assert.ok(Math.round(samples) % RENDER_QUANTUM === 0, `${name}: whole blocks`);
      assert.ok(Math.abs(rate - nominal) / nominal < 0.001, `${name}: ${rate} is within 0.1% of ${nominal}`);
    }
  }
});

test('WAV files: write and read agree', () => {
  const samples = Int16Array.from([0, 1, -1, 32767, -32768, 1234]);
  const back = parseWav(makeWav(samples, 22050));
  assert.equal(back.rate, 22050);
  assert.deepEqual([...back.samples], [...samples]);
  assert.throws(() => parseWav(Buffer.from('nothing like a WAV file at all, but long enough to read a header from')));
});

test('levels and the checks for silence and clipping', () => {
  const lv = levels(Int16Array.from([100, -200, 300]));
  assert.equal(lv.peak, 300);
  assert.throws(() => checkLevels({ name: 'quiet', samples: new Int16Array(1000) }), /silence/);
  assert.throws(() => checkLevels({ name: 'loud', samples: Int16Array.from([0, 32767, -32767, 5000, 0, 3000, -3000]) }), /clipping/);
  assert.doesNotThrow(() => checkLevels({ name: 'fine', samples: Int16Array.from({ length: 1000 }, (_, i) => Math.round(8000 * Math.sin(i / 7))) }));
});

/** A signal with a period of `length` samples, repeated for the intro and three loops. */
function periodic(length, intro, make) {
  const render = new Int16Array(intro + 3 * length);
  for (let i = 0; i < render.length; i++) render[i] = make((i - intro + 3 * length) % length);
  return render;
}

test('cutLoop accepts a signal that repeats exactly, and keeps the second loop', () => {
  const length = 4000;
  const render = periodic(length, 1000, (i) => Math.round(9000 * Math.sin((i / length) * 2 * Math.PI * 25) + 3000 * Math.sin((i / length) * 2 * Math.PI * 131)));
  const { loop, check } = cutLoop(render, 1000 + length, length, 'sine');
  assert.equal(loop.length, length);
  assert.equal(check.diffMax, 0);
  assert.equal(check.joinMax, 0);
  assert.doesNotThrow(() => assertNoShorterLoop(render, 1000 + length, length, 'sine'));
});

test('cutLoop rejects a loop of the wrong length (the join would click)', () => {
  const length = 4000;
  const render = periodic(length, 1000, (i) => Math.round(9000 * Math.sin((i / length) * 2 * Math.PI * 25) + 3000 * Math.sin((i / length) * 2 * Math.PI * 131)));
  assert.throws(() => cutLoop(render, 1000 + length, length - 37, 'short'), /differs|jump/);
});

test('assertNoShorterLoop rejects a loop that is two copies of a shorter one', () => {
  const length = 4000;
  const render = periodic(length, 1000, (i) => Math.round(9000 * Math.sin(((i % (length / 2)) / (length / 2)) * 2 * Math.PI * 7)));
  assert.throws(() => assertNoShorterLoop(render, 1000 + length, length, 'twice'), /repeats after 1\/2/);
});

test('updateManifest replaces the sound lines and keeps the other lines', () => {
  const hash = (c) => c.repeat(64);
  const old = `Copyright (c) 2026 Pawel Gorazda. All rights reserved.\n${hash('a')}  images/room.png\n${hash('b')}  sound/old.wav\n`;
  const text = updateManifest(old, { 'sound/tink.wav': hash('c'), 'sound/bell.wav': hash('d') });
  assert.equal(
    text,
    `Copyright (c) 2026 Pawel Gorazda. All rights reserved.\n${hash('a')}  images/room.png\n${hash('d')}  sound/bell.wav\n${hash('c')}  sound/tink.wav\n`,
  );
  assert.equal(updateManifest(text, { 'sound/bell.wav': hash('d'), 'sound/tink.wav': hash('c') }), text, 'a second update changes nothing');
  assert.ok(updateManifest(null, { 'sound/x.wav': hash('e') }).startsWith('Copyright (c) 2026 Pawel Gorazda.'));
});

test('the files in art/sound/: format, loop length and a join with no jump', () => {
  const tunes = loadTunes();
  for (const [name, tune] of Object.entries(tunes)) {
    const { rate, samples } = parseWav(readFileSync(join(SOUND_DIR, `${name}.wav`)));
    const seconds = MELODY_BARS[name] * TUNE_PASSES * (60 / tune.bpm) * tune.beats;
    assert.equal(rate, loopRate(seconds, DEFAULT_RATE), `${name}: the rate`);
    assert.equal(samples.length, Math.round(seconds * rate), `${name}: the length is the loop`);
    assert.ok(samples.length % RENDER_QUANTUM === 0, `${name}: whole blocks`);
    let steps = 0;
    for (let i = 1; i < samples.length; i++) steps = Math.max(steps, Math.abs(samples[i] - samples[i - 1]));
    assert.ok(Math.abs(samples[0] - samples[samples.length - 1]) <= steps, `${name}: the join is no larger than the largest step`);
  }
  for (const name of Object.keys(EFFECTS)) {
    const { rate, samples } = parseWav(readFileSync(join(SOUND_DIR, `${name}.wav`)));
    assert.equal(rate, DEFAULT_RATE, `${name}: the rate`);
    assert.doesNotThrow(() => checkLevels({ name, samples }));
    assert.ok(Math.abs(samples[samples.length - 1]) <= 8, `${name}: ends in silence`);
  }
});
