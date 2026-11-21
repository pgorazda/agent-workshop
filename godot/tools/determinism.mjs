#!/usr/bin/env node
// Checks that a scene gives the same frames and the same sound on every run. It records the scene two times (or
// more) with tools/record.mjs's engine arguments, hashes every PNG frame and the WAV file with SHA-256, and compares the runs. It needs
// a real window and the Godot editor, not ffmpeg.
//
//   node tools/determinism.mjs                          # the scene session, two runs, with the tune krakowiak
//   node tools/determinism.mjs --scene tour --runs 3
//   node tools/determinism.mjs --scene multi --music off --keep out/determinism
//
// What it covers: one machine, one Godot build, one GPU and driver, runs one after the other. What it does not cover: another machine,
// another driver, another operating system, or the Linux container (see godot/README.md).

import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs, recordFrames } from './record.mjs';

const sha256 = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');

/** The hash of every frame (in order) and of the WAV file of a folder that a recording wrote. */
export function hashFolder(dir) {
  const frames = readdirSync(dir).filter((name) => /^f\d{8}\.png$/.test(name)).sort();
  return { frames: frames.map((name) => sha256(path.join(dir, name))), wav: sha256(path.join(dir, 'f.wav')) };
}

/** Compares two results of `hashFolder`: the numbers of frames, the frames that differ, and whether the WAV files are equal. */
export function compareHashes(a, b) {
  const differing = [];
  for (let i = 0; i < Math.min(a.frames.length, b.frames.length); i += 1) if (a.frames[i] !== b.frames[i]) differing.push(i);
  return { framesA: a.frames.length, framesB: b.frames.length, differing, wavEqual: a.wav === b.wav, same: a.frames.length === b.frames.length && differing.length === 0 && a.wav === b.wav };
}

async function main() {
  const argv = process.argv.slice(2);
  let runs = 2;
  let keep = '';
  const rest = [];
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--runs') { runs = Number(argv[i + 1]); i += 1; } else if (argv[i] === '--keep') { keep = argv[i + 1]; i += 1; } else rest.push(argv[i]);
  }
  const opts = parseArgs(rest);
  const base = keep ? path.resolve(keep) : path.join(tmpdir(), `agent-workshop-determinism-${process.pid}`);
  mkdirSync(base, { recursive: true });
  const hashes = [];
  try {
    for (let run = 0; run < runs; run += 1) {
      const dir = path.join(base, `run${run}`);
      rmSync(dir, { recursive: true, force: true });
      const result = await recordFrames(opts, dir);
      hashes.push(hashFolder(dir));
      console.log(`run ${run + 1}: ${result.written} frames, WAV ${hashes[run].wav.slice(0, 12)}`);
      if (!keep) { for (const name of readdirSync(dir)) if (/\.png$/.test(name)) rmSync(path.join(dir, name)); }
    }
  } finally {
    if (!keep) rmSync(base, { recursive: true, force: true });
  }
  let ok = true;
  for (let run = 1; run < runs; run += 1) {
    const result = compareHashes(hashes[0], hashes[run]);
    console.log(`run 1 against run ${run + 1}: ${result.framesA} and ${result.framesB} frames, ${result.differing.length} frames differ${result.differing.length ? ` (first: ${result.differing.slice(0, 10).join(', ')})` : ''}, WAV ${result.wavEqual ? 'equal' : 'DIFFERENT'}`);
    ok &&= result.same;
  }
  if (keep) writeFileSync(path.join(base, 'hashes.json'), JSON.stringify(hashes));
  console.log(ok ? `same: scene ${opts.scene}, ${runs} runs, every frame and the WAV file agree` : 'DIFFERENT: the runs do not agree');
  process.exitCode = ok ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exit(1); });
}
