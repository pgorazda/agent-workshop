#!/usr/bin/env node
// Renders the sound files of the Godot client: four tunes (one exact loop each) and five event sounds.
//
//   cd godot
//   node tools/render-sound.mjs                    # writes art/sound/*.wav and the sound lines of art/MANIFEST.txt
//   node tools/render-sound.mjs --rate 44100       # another sample rate (the default is DEFAULT_RATE)
//   node tools/render-sound.mjs --out some/folder  # writes there; the manifest stays as it is
//   node tools/render-sound.mjs --check            # renders again and compares with art/sound/ and the manifest; writes nothing
//
// The tool opens art/sound_src/sound.js in headless Chromium and calls its offline render (OfflineAudioContext), as
// the old JavaScript mockup did. Nothing is synthesised when the client runs. It needs Playwright and a Chromium:
//
//   npm install --no-save playwright               # here, or set PLAYWRIGHT_DIR
//   export CHROMIUM_PATH=/path/to/chrome           # a Chrome or Chromium that you have
//
// A render gives the same bytes every time (checked with two separate runs, see README.md). Chromium alone does not:
// see deterministicSums.
//
// The loop of a tune. sound.js plays a tune as an intro and then the melody again and again. The lead's sound
// depends on the number of the pass and has two values, so one loop is two passes of the melody (TUNE_PASSES).
// A note or a release tail may cross the end of the loop, and the gentle limiter of the mix (a compressor) keeps
// a state. So the tool renders the intro and three loops in one go and keeps the second loop. The loop then starts
// with the tails of the loop before it and ends where the tails flow into the loop after it. For the third loop to
// equal the second one, sample for sample, the tool needs three helpers (each is explained near its code):
//   loopRate          the sample rate of a tune is moved a little (0.07% at most), so that the loop is a whole
//                     number of the 128-sample blocks that Chromium renders in
//   tunePatch         the noise hits depend on the time inside the loop, and every time gets a tiny fixed nudge
//   deterministicSums a node adds two inputs at most, so that the sum does not depend on memory addresses
// The tool proves the loop in this way: the third loop must equal the second (no sample differs by more than 2 steps
// of 16 bits), the samples around the join must equal the same place in the continuous render, the jump at the join
// must not exceed the largest step inside the loop, and the loop must not be a repeat of a shorter loop.

import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const GODOT_DIR = fileURLToPath(new URL('..', import.meta.url));
const SOUND_JS = join(GODOT_DIR, 'art', 'sound_src', 'sound.js');
const DEFAULT_OUT = join(GODOT_DIR, 'art', 'sound');
const MANIFEST = join(GODOT_DIR, 'art', 'MANIFEST.txt');
const MANIFEST_FIRST_LINE = 'Copyright (c) 2026 Pawel Gorazda. All rights reserved.';

/** The sample rate of the files in the repository. See "Sound" in the README of godot/. */
export const DEFAULT_RATE = 22050;

/**
 * The bars in one pass of each melody. Counted from sound.js: the sections of `melody`.
 * krakowiak: 4 sections of 8 bars. kujawiak: 2 of 8. oberek: 4 of 8. goralski: 4 of 5.
 * `tools/render-sound.test.mjs` checks these numbers (and INTRO_BARS and TUNE_PASSES) against sound.js.
 */
export const MELODY_BARS = { krakowiak: 32, kujawiak: 16, oberek: 32, goralski: 20 };
/** The bars before the melody in each tune: `intro` in sound.js. */
export const INTRO_BARS = { krakowiak: 2, kujawiak: 1, oberek: 2, goralski: 2 };
/** The passes in one loop: the lead's sound alternates between two sounds, one for each pass. */
export const TUNE_PASSES = 2;
/** The event sounds. The number is the length to render, in seconds. The tool cuts the silence at the end. */
export const EFFECTS = { tink: 0.5, bell: 1.6, flop: 1.0, chime: 0.9, fanfare: 1.2 };

/** The same function as `mulberry32` in art/image_src/base.js. sound.js needs it as a global name. */
const MULBERRY32 = `function mulberry32(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }`;

const CLIP_LEVEL = 32767; // a sample at full scale means that the limiter did not hold, or that the render clamped
const SILENCE_RMS_DB = -60; // a file quieter than this is silent
const TAIL_LEVEL = 4; // the end of an event sound: the last sample above this level, in 16-bit steps
const LOOP_MAX_DIFF = 2; // loop 3 equals loop 2: no sample differs by more than this, in 16-bit steps (rounding of the render)
const SEAM_STEP_LIMIT = 1; // the jump at the join is at most this multiple of the largest step inside the loop
const SHORTER_LOOP_RMS = 0.05; // a shorter loop exists when the loop equals itself, shifted, within this much of its RMS

// ---------------------------------------------------------------- WAV and levels

/** Reads a 16-bit mono PCM WAV (the format that sound.js writes). Returns { rate, samples }. */
export function parseWav(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (offset) => String.fromCharCode(v.getUint8(offset), v.getUint8(offset + 1), v.getUint8(offset + 2), v.getUint8(offset + 3));
  if (tag(0) !== 'RIFF' || tag(8) !== 'WAVE' || tag(12) !== 'fmt ' || tag(36) !== 'data') throw new Error('not a WAV file in the expected layout');
  if (v.getUint16(20, true) !== 1 || v.getUint16(22, true) !== 1 || v.getUint16(34, true) !== 16) throw new Error('the WAV file is not 16-bit mono PCM');
  const rate = v.getUint32(24, true);
  const count = v.getUint32(40, true) / 2;
  const samples = new Int16Array(count);
  for (let i = 0; i < count; i++) samples[i] = v.getInt16(44 + i * 2, true);
  return { rate, samples };
}

/** Writes a 16-bit mono PCM WAV with the 44-byte header that sound.js writes. */
export function makeWav(samples, rate) {
  const bytes = Buffer.alloc(44 + samples.length * 2);
  bytes.write('RIFF', 0, 'latin1');
  bytes.writeUInt32LE(36 + samples.length * 2, 4);
  bytes.write('WAVEfmt ', 8, 'latin1');
  bytes.writeUInt32LE(16, 16);
  bytes.writeUInt16LE(1, 20);
  bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(rate, 24);
  bytes.writeUInt32LE(rate * 2, 28);
  bytes.writeUInt16LE(2, 32);
  bytes.writeUInt16LE(16, 34);
  bytes.write('data', 36, 'latin1');
  bytes.writeUInt32LE(samples.length * 2, 40);
  for (let i = 0; i < samples.length; i++) bytes.writeInt16LE(samples[i], 44 + i * 2);
  return bytes;
}

export function levels(samples) {
  let peak = 0;
  let sum = 0;
  for (const s of samples) {
    const a = Math.abs(s);
    if (a > peak) peak = a;
    sum += s * s;
  }
  const rms = Math.sqrt(sum / Math.max(1, samples.length));
  const db = (x) => (x > 0 ? 20 * Math.log10(x / 32768) : -Infinity);
  return { peak, rms, peakDb: db(peak), rmsDb: db(rms) };
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

// ---------------------------------------------------------------- the loop

/** Chromium renders audio in blocks of this many samples. A note is placed in a block, so the place in the block counts. */
export const RENDER_QUANTUM = 128;

/**
 * The sample rate for a tune: the whole number nearest to `nominal` at which the loop (`seconds` long) is a whole
 * number of render blocks. Chromium places a note by its place inside a block of 128 samples, and with a sub-sample
 * shift. A loop that is a whole number of blocks puts every note at the same place in each pass, so the passes are
 * equal. Any other length gives a loop that differs from the next one in every note. The change of rate is small
 * (at most 0.07% from 22050 or 44100 Hz). The file keeps this rate, and Godot plays it at the right speed.
 */
export function loopRate(seconds, nominal) {
  for (let delta = 0; delta <= 400; delta++) {
    for (const rate of delta === 0 ? [nominal] : [nominal - delta, nominal + delta]) {
      const blocks = (seconds * rate) / RENDER_QUANTUM;
      if (Math.abs(blocks - Math.round(blocks)) < 1e-9) return rate;
    }
  }
  throw new Error(`no loop rate near ${nominal} Hz for a loop of ${seconds} s`);
}

/**
 * Cuts the second loop out of a render of the intro and three loops, and checks that the loop has no join.
 * `render` holds the samples, `start` is the first sample of the second loop (the loop starts at a bar line),
 * `length` is the loop length in samples. Returns { loop, check } and throws when a check fails.
 */
export function cutLoop(render, start, length, name = 'loop') {
  if (start + 2 * length > render.length) throw new Error(`${name}: the render is too short for three loops`);
  const loop = render.slice(start, start + length);
  const next = render.subarray(start + length, start + 2 * length);
  const { rms, peak } = levels(loop);

  // 1. The third loop equals the second one: the loop is periodic, with the state of the limiter included.
  let diffSum = 0;
  let diffMax = 0;
  for (let i = 0; i < length; i++) {
    const d = Math.abs(loop[i] - next[i]);
    diffSum += d * d;
    if (d > diffMax) diffMax = d;
  }
  const diffRms = Math.sqrt(diffSum / length);

  // 2. The join. After the last sample comes the first one. The continuous render has the same place between
  //    loop 2 and loop 3: its samples there are the reference. The samples around the join must be equal to them.
  const SPAN = Math.min(4096, length >> 1);
  let joinMax = 0;
  for (let k = -SPAN; k < SPAN; k++) {
    const wrapped = loop[(k + length) % length];
    const reference = render[start + length + k];
    joinMax = Math.max(joinMax, Math.abs(wrapped - reference));
  }
  // The jump at the join, against the steps inside the loop. A click is a jump that no step in the loop has.
  const jump = Math.abs(loop[0] - loop[length - 1]);
  let stepMax = 0;
  let stepSum = 0;
  for (let i = 1; i < length; i++) {
    const step = Math.abs(loop[i] - loop[i - 1]);
    if (step > stepMax) stepMax = step;
    stepSum += step;
  }
  const stepMean = stepSum / (length - 1);

  // 3. No shorter loop: the loop shifted by a proper divisor of its bars does not equal itself.
  const check = { diffMax, diffRms, rms, peak, joinMax, jump, stepMax, stepMean, shorter: [] };
  const problems = [];
  if (diffMax > LOOP_MAX_DIFF) problems.push(`loop 3 differs from loop 2 (largest difference ${diffMax}, RMS ${diffRms.toFixed(2)} of ${rms.toFixed(0)})`);
  if (joinMax > LOOP_MAX_DIFF) problems.push(`the samples around the join differ from the continuous render by ${joinMax}`);
  if (jump > SEAM_STEP_LIMIT * stepMax) problems.push(`the jump at the join (${jump}) is larger than any step in the loop (${stepMax})`);
  if (problems.length) throw new Error(`${name}: ${problems.join('; ')}`);
  return { loop, check };
}

/** The shorter periods (in samples) to test: the loop split into 2, 3, 4, 5 or 6 equal parts. */
export function shorterLoopShifts(length) {
  return [2, 3, 4, 5, 6].map((parts) => ({ parts, shift: Math.round(length / parts) }));
}

/** Throws when the loop repeats itself with a shorter period. */
export function assertNoShorterLoop(render, start, length, name = 'loop') {
  const { rms } = levels(render.subarray(start, start + length));
  for (const { parts, shift } of shorterLoopShifts(length)) {
    // Compare the loop with the render `shift` samples later, over the whole loop.
    let sum = 0;
    for (let i = 0; i < length; i++) {
      const d = render[start + i] - render[start + i + shift];
      sum += d * d;
    }
    const ratio = Math.sqrt(sum / length) / rms;
    if (ratio < SHORTER_LOOP_RMS) throw new Error(`${name}: the sound repeats after 1/${parts} of the loop, so the loop is too long`);
  }
}

// ---------------------------------------------------------------- the browser

function loadPlaywright() {
  const roots = [process.env.PLAYWRIGHT_DIR, GODOT_DIR].filter(Boolean);
  for (const root of roots) {
    try {
      return createRequire(join(root, 'noop.js'))('playwright');
    } catch {
      // try the next place
    }
  }
  throw new Error(`Playwright was not found. Install it ("npm install --no-save playwright") in one of: ${roots.join(', ')}`);
}

export async function openSynthesiser() {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (err) => errors.push(err.message));
  await page.setContent('<!doctype html><meta charset="utf-8"><title>sound</title>');
  await page.addScriptTag({ content: MULBERRY32 });
  await page.addScriptTag({ path: SOUND_JS });
  const ok = await page.evaluate(() => typeof window.SoundArt?.render === 'function' && typeof OfflineAudioContext === 'function');
  if (!ok || errors.length) throw new Error(`the synthesiser did not load: ${errors.join('; ') || 'SoundArt.render or OfflineAudioContext is missing'}`);
  await deterministicSums(page);
  return { browser, page };
}

/**
 * Makes the sum of many inputs the same in every run. Chromium adds the inputs of a node in an order that depends on
 * the memory addresses of the nodes. Float addition is not associative, so a node with three or more inputs gives
 * a result that differs by one unit of the last float digit from run to run. That moves a few samples by one step of
 * the 16-bit output. The patch lets a node have two inputs at most: a third source and the later ones go into a chain
 * of gain nodes (gain 1), and each node of the chain adds two inputs. The sum of two numbers does not depend on their
 * order, so the result is the same in every run. The sound is the same up to rounding of the sum.
 */
async function deterministicSums(page) {
  await page.evaluate(() => {
    const original = AudioNode.prototype.connect;
    const disconnect = AudioNode.prototype.disconnect;
    const sinks = new WeakMap();
    AudioNode.prototype.connect = function (destination, ...rest) {
      if (!(destination instanceof AudioNode) || rest.length) return original.call(this, destination, ...rest);
      let sink = sinks.get(destination);
      if (!sink) sinks.set(destination, (sink = { sources: [], chain: null }));
      if (sink.sources.push(this) <= 2) return original.call(this, destination);
      const link = destination.context.createGain();
      if (sink.chain === null) {
        const first = destination.context.createGain();
        original.call(first, destination);
        for (const source of sink.sources.slice(0, 2)) {
          disconnect.call(source, destination);
          original.call(source, first);
        }
        sink.chain = first;
      }
      disconnect.call(sink.chain, destination);
      original.call(sink.chain, link);
      original.call(this, link);
      original.call(link, destination);
      sink.chain = link;
      return destination;
    };
  });
}

/**
 * Two small changes to how a tune is scheduled, so that every pass of the loop renders the same. They change the
 * scheduling calls of the page, not sound.js. `stopTunePatch` puts the original calls back.
 *
 * 1. Noise. sound.js starts each noise hit at a place in its noise buffer that depends on the absolute time:
 *    `(at * 7.31) % 0.5`. So the same bar sounds a little different in each pass. The patch makes the place depend
 *    on the time inside the loop. A hit keeps its time, level and filter. Only the slice of the seeded noise changes.
 * 2. A time nudge. A note time is a sum of doubles, and the sum differs by about 1e-13 s from one pass to the next.
 *    When a note falls on a whole sample, that difference can put the note on the sample before or after. The patch
 *    adds NUDGE samples (about 5 us, a small fraction of a sample) to every time of the tune. No note is then near a
 *    sample boundary, and the same note falls on the same sample in every pass. All notes move by the same time.
 */
export const NUDGE = 0.1234;
export async function tunePatch(page, loopStart, loopLength, rate) {
  await page.evaluate(
    ([from, length, nudge, sampleRate]) => {
      if (window.__patched) throw new Error('the tune patch is already on');
      const shift = nudge / sampleRate;
      const saved = (window.__patched = []);
      const wrap = (proto, name, make) => {
        saved.push([proto, name, proto[name]]);
        proto[name] = make(proto[name]);
      };
      for (const name of ['setValueAtTime', 'linearRampToValueAtTime', 'exponentialRampToValueAtTime']) {
        wrap(AudioParam.prototype, name, (original) => function (value, time) { return original.call(this, value, time + shift); });
      }
      wrap(AudioScheduledSourceNode.prototype, 'start', (original) => function (when) { return original.call(this, when + shift); });
      wrap(AudioScheduledSourceNode.prototype, 'stop', (original) => function (when) { return original.call(this, when + shift); });
      wrap(AudioBufferSourceNode.prototype, 'start', (original) => function (when, offset, duration) {
        const phase = Math.round((((when - from) % length) + length) % length * 1e6) / 1e6;
        return original.call(this, when + shift, (phase * 7.31) % 0.5, duration);
      });
    },
    [loopStart, loopLength, NUDGE, rate],
  );
}
export async function stopTunePatch(page) {
  await page.evaluate(() => {
    for (const [proto, name, original] of window.__patched ?? []) proto[name] = original;
    window.__patched = null;
  });
}

/** Calls SoundArt.render in the page. Returns the WAV bytes. */
export async function renderWav(page, duration, cues, options, rate) {
  const base64 = await page.evaluate(([d, c, o, r]) => window.SoundArt.render(d, c, o, r), [duration, cues, options, rate]);
  return Buffer.from(base64, 'base64');
}

// ---------------------------------------------------------------- the files

/** Renders the nine sounds. Returns [{ name, kind, rate, samples, ... }] in a fixed order. `rate` is the nominal rate. */
export async function renderAll(rate = DEFAULT_RATE, log = () => {}) {
  const { browser, page } = await openSynthesiser();
  try {
    const bars = await page.evaluate((names) => Object.fromEntries(names.map((n) => [n, window.SoundArt.barOf(n)])), Object.keys(MELODY_BARS));
    const out = [];
    for (const name of Object.keys(MELODY_BARS)) {
      const bar = bars[name];
      const introBars = INTRO_BARS[name];
      const loopBars = MELODY_BARS[name] * TUNE_PASSES;
      const seconds = loopBars * bar;
      const tuneRate = loopRate(seconds, rate);
      const length = Math.round(seconds * tuneRate);
      const start = Math.round((introBars + loopBars) * bar * tuneRate);
      const duration = (introBars + 3 * loopBars) * bar + 0.1;
      log(`${name}: ${loopBars} bars of ${bar.toFixed(6)} s = ${seconds.toFixed(3)} s at ${tuneRate} Hz = ${length} samples; rendering ${duration.toFixed(1)} s ...`);
      await tunePatch(page, introBars * bar, seconds, tuneRate);
      const wav = parseWav(await renderWav(page, duration, [], { tune: name, events: false }, tuneRate));
      await stopTunePatch(page);
      if (wav.rate !== tuneRate) throw new Error(`${name}: the render has the rate ${wav.rate}`);
      const { loop, check } = cutLoop(wav.samples, start, length, name);
      assertNoShorterLoop(wav.samples, start, length, name);
      out.push({ name, kind: 'tune', rate: tuneRate, samples: loop, seconds, bars: loopBars, check });
    }
    for (const [name, seconds] of Object.entries(EFFECTS)) {
      const full = parseWav(await renderWav(page, seconds, [{ t: 0, name }], { tune: null, events: true }, rate)).samples;
      // The compressor of the mix delays the sound by a few milliseconds: cut the zeros before it. Then cut the
      // silence after the sound. The render must be long enough to hold the whole tail.
      let first = 0;
      while (first < full.length && full[first] === 0) first++;
      let last = full.length - 1;
      while (last > first && Math.abs(full[last]) <= TAIL_LEVEL) last--;
      if (last > full.length - Math.round(rate * 0.02)) throw new Error(`${name}: the sound is still going at the end of the render (${seconds} s)`);
      const end = Math.min(full.length, last + 1 + Math.round(rate * 0.005));
      out.push({ name, kind: 'effect', rate, samples: full.slice(first, end), seconds: (end - first) / rate, latency: first / rate });
    }
    return out;
  } finally {
    await browser.close();
  }
}

/** Fails on silence and on clipping. Returns the levels. */
export function checkLevels(item) {
  const lv = levels(item.samples);
  if (lv.peak >= CLIP_LEVEL) throw new Error(`${item.name}: clipping (a sample at full scale)`);
  if (lv.rmsDb < SILENCE_RMS_DB) throw new Error(`${item.name}: silence (RMS ${lv.rmsDb.toFixed(1)} dBFS)`);
  return lv;
}

const fmt = (x, n = 1) => (Number.isFinite(x) ? x.toFixed(n) : '-inf');

export function report(items, rate) {
  const lines = [`nominal sample rate ${rate} Hz, mono, 16 bit`, 'file            rate Hz   length s   samples   peak (LSB / dBFS)   RMS dBFS      bytes'];
  let total = 0;
  const rows = [];
  for (const item of items) {
    const lv = checkLevels(item);
    const bytes = 44 + item.samples.length * 2;
    total += bytes;
    rows.push({ name: item.name, bytes, ...lv });
    lines.push(
      `${(item.name + '.wav').padEnd(15)} ${String(item.rate).padStart(7)} ${item.seconds.toFixed(3).padStart(8)} ${String(item.samples.length).padStart(9)}   ${String(lv.peak).padStart(5)} / ${fmt(lv.peakDb).padStart(6)}   ${fmt(lv.rmsDb).padStart(8)}   ${String(bytes).padStart(9)}`,
    );
  }
  lines.push(`total ${total} bytes (${(total / 1048576).toFixed(2)} MiB, ${(total / 1e6).toFixed(2)} MB)`);
  return { text: lines.join('\n'), total, rows };
}

export function reportLoops(items) {
  const lines = ['loop checks (tunes): loop 3 against loop 2, and the join'];
  lines.push('tune          bars   loop 3 - loop 2: max / RMS      join vs continuous render   jump   largest step / mean step');
  for (const item of items.filter((i) => i.kind === 'tune')) {
    const c = item.check;
    lines.push(
      `${item.name.padEnd(13)} ${String(item.bars).padStart(4)}   ${String(c.diffMax).padStart(6)} / ${c.diffRms.toFixed(2).padStart(7)} (of RMS ${c.rms.toFixed(0)})   ${String(c.joinMax).padStart(16)}   ${String(c.jump).padStart(8)}   ${c.stepMax} / ${c.stepMean.toFixed(1)}`,
    );
  }
  return lines.join('\n');
}

/** The lines of MANIFEST.txt for the sound files, and a new manifest that keeps the other lines. */
export function updateManifest(text, hashes) {
  const own = /^[0-9a-f]{64} {2}sound\//;
  const keep = (text ?? `${MANIFEST_FIRST_LINE}\n`).replace(/\r\n/g, '\n').split('\n').filter((line) => !own.test(line));
  while (keep.length && keep[keep.length - 1] === '') keep.pop();
  const lines = Object.keys(hashes).sort().map((file) => `${hashes[file]}  ${file}`);
  return `${[...keep, ...lines].join('\n')}\n`;
}

// ---------------------------------------------------------------- the command

async function main() {
  const args = process.argv.slice(2);
  const option = (name, fallback) => (args.includes(name) ? args[args.indexOf(name) + 1] : fallback);
  const rate = Number(option('--rate', DEFAULT_RATE));
  const outDir = resolve(option('--out', DEFAULT_OUT));
  const check = args.includes('--check');
  if (![22050, 44100].includes(rate)) throw new Error('--rate must be 22050 or 44100');

  const items = await renderAll(rate, (line) => console.error(line));
  console.log(report(items, rate).text);
  console.log(reportLoops(items));

  const files = {};
  for (const item of items) files[`${item.name}.wav`] = makeWav(item.samples, item.rate);
  const hashes = Object.fromEntries(Object.entries(files).map(([file, bytes]) => [`sound/${file}`, sha256(bytes)]));

  if (check) {
    const problems = [];
    for (const [file, bytes] of Object.entries(files)) {
      const path = join(outDir, file);
      if (!existsSync(path)) problems.push(`${file}: the file is missing`);
      else if (sha256(readFileSync(path)) !== sha256(bytes)) problems.push(`${file}: a new render gives other bytes`);
    }
    if (outDir === DEFAULT_OUT) {
      const manifest = existsSync(MANIFEST) ? readFileSync(MANIFEST, 'utf8') : '';
      for (const [file, hash] of Object.entries(hashes)) if (!manifest.includes(`${hash}  ${file}`)) problems.push(`MANIFEST.txt: the line of ${file} is missing or old`);
    }
    if (problems.length) throw new Error(problems.join('\n'));
    console.log('check: all nine files equal a new render');
    return;
  }

  mkdirSync(outDir, { recursive: true });
  for (const [file, bytes] of Object.entries(files)) writeFileSync(join(outDir, file), bytes);
  console.log(`wrote ${Object.keys(files).length} files to ${outDir}`);
  if (outDir === DEFAULT_OUT) {
    writeFileSync(MANIFEST, updateManifest(existsSync(MANIFEST) ? readFileSync(MANIFEST, 'utf8') : null, hashes));
    console.log('updated the sound lines of art/MANIFEST.txt');
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(`error: ${err.message}`);
    process.exitCode = 1;
  });
}
