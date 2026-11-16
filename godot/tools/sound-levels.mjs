// Measures the levels of the sound files when a tune and an event sound play together (phase G-7).
//
//   node tools/sound-levels.mjs                 the table, for the files in art/sound/
//   node tools/sound-levels.mjs --hop 64        a finer search for the share of start times (slower)
//   node tools/sound-levels.mjs --music-db -6   another volume of the tune (the player uses -3 dB)
//   node tools/sound-levels.mjs --json          the numbers as JSON
//
// Each file carries its own gentle limiter (the mixer of the mockup), so each file alone stays below full scale. Two files that
// play at the same time add up. The player puts a limiter on the master bus (`AudioEffectHardLimiter`, see `src/view/sound_player.gd`).
// This tool says how far the sum of a tune and one event sound goes above full scale before that limiter, for the worst start time of
// the event, and for what share of start times the sum is above full scale. It adds the samples as if both files had the same rate
// (the rates differ by 0.1% at most), and it lets the tune wrap round, as a loop does.
//
// It does not model the limiter, the resampling of the engine or the pool of event sounds (more than one event at once). A person
// must still listen: a level is not a judgement of how a sound is.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { levels, parseWav } from './render-sound.mjs';

export const GODOT = fileURLToPath(new URL('..', import.meta.url));
export const SOUND_DIR = join(GODOT, 'art', 'sound');
export const TUNES = ['krakowiak', 'kujawiak', 'oberek', 'goralski'];
export const EVENTS = ['tink', 'bell', 'flop', 'chime', 'fanfare'];
/** Where the master limiter stops the level, in dBFS (`LIMITER_CEILING_DB` in `src/view/sound_player.gd`). */
export const LIMITER_CEILING_DB = -1.0;
/** The volume of the tune player in dB (`MUSIC_VOLUME_DB` in `src/view/sound_player.gd`): headroom for the event sounds. */
export const MUSIC_VOLUME_DB = -3.0;
const BLOCK = 64;

export const toDb = (lsb) => (lsb > 0 ? 20 * Math.log10(lsb / 32768) : -Infinity);

export function loadSound(name, dir = SOUND_DIR) {
  return parseWav(new Uint8Array(readFileSync(join(dir, `${name}.wav`)))).samples;
}

/** The largest absolute sample of each block of BLOCK samples. */
function blockPeaks(samples) {
  const out = new Int32Array(Math.ceil(samples.length / BLOCK));
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > out[(i / BLOCK) | 0]) out[(i / BLOCK) | 0] = a;
  }
  return out;
}

/** The peak of tune + event when the event starts at sample `offset` of the tune (the tune wraps round). */
export function peakAt(tune, event, offset) {
  const n = tune.length;
  let peak = 0;
  for (let i = 0; i < event.length; i++) {
    const a = Math.abs(tune[(offset + i) % n] + event[i]);
    if (a > peak) peak = a;
  }
  return peak;
}

/**
 * The sum of a tune and an event sound. Returns { worst, worstAt, share0, share1, offsets }:
 *   worst    the largest peak over all start times, in LSB (above 32767 means above full scale)
 *   share0   the share of the start times (one every `hop` samples) at which the sum goes above full scale
 *   share1   the share at which it goes above the ceiling of the limiter
 * The worst start time is found with the peaks of blocks as an upper bound, and then each promising block is searched sample by sample.
 */
export function mixLevels(tuneIn, event, hop = 256, musicDb = MUSIC_VOLUME_DB) {
  const gain = 10 ** (musicDb / 20);
  const tune = gain === 1 ? tuneIn : Float64Array.from(tuneIn, (v) => v * gain);
  const n = tune.length;
  const ceiling = 32768 * 10 ** (LIMITER_CEILING_DB / 20);
  let over0 = 0;
  let over1 = 0;
  let offsets = 0;
  for (let o = 0; o < n; o += hop) {
    const p = peakAt(tune, event, o);
    offsets += 1;
    if (p >= 32768) over0 += 1;
    if (p >= ceiling) over1 += 1;
  }
  const et = blockPeaks(tune);
  const ee = blockPeaks(event);
  const nb = et.length;
  const bounds = [];
  for (let b = 0; b < nb; b++) {
    let bound = 0;
    for (let k = 0; k < ee.length; k++) {
      const v = Math.max(et[(b + k) % nb], et[(b + k + 1) % nb]) + ee[k];
      if (v > bound) bound = v;
    }
    bounds.push([bound, b]);
  }
  bounds.sort((x, y) => y[0] - x[0]);
  let worst = 0;
  let worstAt = 0;
  for (const [bound, b] of bounds) {
    if (bound <= worst) break;
    for (let r = 0; r < BLOCK; r++) {
      const o = b * BLOCK + r;
      if (o >= n) break;
      const p = peakAt(tune, event, o);
      if (p > worst) {
        worst = p;
        worstAt = o;
      }
    }
  }
  return { worst, worstAt, share0: over0 / offsets, share1: over1 / offsets, offsets };
}

export function analyse(hop = 256, dir = SOUND_DIR, musicDb = MUSIC_VOLUME_DB) {
  const events = EVENTS.map((name) => ({ name, samples: loadSound(name, dir) }));
  const rows = [];
  for (const tuneName of TUNES) {
    const tune = loadSound(tuneName, dir);
    for (const event of events) {
      const m = mixLevels(tune, event.samples, hop, musicDb);
      rows.push({
        tune: tuneName,
        event: event.name,
        tunePeakDb: levels(tune).peakDb + musicDb,
        eventPeakDb: levels(event.samples).peakDb,
        sumOfPeaksDb: toDb(levels(tune).peak * 10 ** (musicDb / 20) + levels(event.samples).peak),
        worstDb: toDb(m.worst),
        worstAtSeconds: m.worstAt / 22050,
        shareOverFull: m.share0,
        shareOverCeiling: m.share1,
      });
    }
  }
  return rows;
}

const f = (x, n = 1) => (Number.isFinite(x) ? x.toFixed(n) : '-inf');

function main() {
  const args = process.argv.slice(2);
  const hop = args.includes('--hop') ? Number(args[args.indexOf('--hop') + 1]) : 256;
  const musicDb = args.includes('--music-db') ? Number(args[args.indexOf('--music-db') + 1]) : MUSIC_VOLUME_DB;
  const rows = analyse(hop, SOUND_DIR, musicDb);
  if (args.includes('--json')) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }
  console.log(`start times: one every ${hop} samples; limiter ceiling ${LIMITER_CEILING_DB} dBFS; tune volume ${musicDb} dB`);
  console.log('tune        event     tune peak  event peak  sum of peaks  worst sum  over 0 dBFS  over ceiling');
  for (const r of rows) {
    console.log(
      `${r.tune.padEnd(11)} ${r.event.padEnd(8)} ${f(r.tunePeakDb).padStart(9)} ${f(r.eventPeakDb).padStart(11)} ${f(r.sumOfPeaksDb).padStart(13)} ${f(r.worstDb).padStart(10)} ${(f(r.shareOverFull * 100) + ' %').padStart(12)} ${(f(r.shareOverCeiling * 100) + ' %').padStart(13)}`,
    );
  }
  const worst = rows.reduce((a, b) => (b.worstDb > a.worstDb ? b : a));
  console.log(`\nworst of all: ${worst.tune} + ${worst.event} reaches ${f(worst.worstDb)} dBFS before the master limiter (at ${f(worst.worstAtSeconds, 2)} s of the tune).`);
  console.log(`The limiter must take ${f(worst.worstDb - LIMITER_CEILING_DB)} dB off at that moment to hold ${LIMITER_CEILING_DB} dBFS.`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
