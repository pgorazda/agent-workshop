#!/usr/bin/env node
// Records a scene of the Godot client, frame by frame, and encodes it with ffmpeg (phase G-8). It is the counterpart of the
// recorder of the old JavaScript mockup (removed, see the git history) and keeps its options.
//
//   cd godot
//   node tools/record.mjs                          # out/session.mp4 (1920x1080, about 28 s)
//   node tools/record.mjs --scene multi            # several agents: out/multi.mp4
//   node tools/record.mjs --scene arenas|many|follow|ten|tour
//   node tools/record.mjs --stills 7,14.4,22.5     # out/still-session-<seconds>.png only (480x270)
//   options: --fps 30  --out out/name.mp4  --scene session|multi|arenas|many|follow|ten|tour
//            --reduced (the cut instead of the slide)  --silent (no sound track)
//            --music krakowiak|kujawiak|oberek|goralski|off  --events 0 (no event sounds)
//            --menu <seconds> (the sound menu is open for the first seconds)  --no-switch (the sound switch is not drawn)
//            --keep-frames (keep the PNG files and the WAV file)  --godot-arg <arg> (more arguments for the engine; may repeat)
//
// How it works: the client (`src/view/live_view.gd`) runs in recording mode inside the engine's Movie Maker (`--write-movie`,
// `--fixed-fps`). Godot writes one PNG file for each frame (480x270) and one WAV file (48 kHz, stereo, 32 bit). The WAV holds what the
// client played: the tune and the event sounds. This tool then calls ffmpeg: a 4x integer scale with no smoothing (1920x1080),
// libx264 for the picture and AAC for the sound. The recording needs a real window (not --headless). It checks that no two penguins
// stand on one spot at the same time, as the old mockup recorder did, and exits with an error if they do.
//
// Needs the Godot editor (GODOT, see godot/README.md) and ffmpeg with libx264 on the PATH (or FFMPEG=<path>). If ffmpeg is missing,
// the tool says so, keeps the frames, and writes the commands to <out>.ffmpeg.txt. The same scene gives the same frames on every run
// of one machine and one build (see tools/determinism.mjs).

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';

export const SCENES = ['session', 'multi', 'arenas', 'many', 'follow', 'ten', 'tour'];
export const TUNES = ['krakowiak', 'kujawiak', 'oberek', 'goralski'];
export const DEFAULT_OUT_DIR = path.join(GODOT_DIR, 'out');
/** The mix rate of Movie Maker (the project setting `editor/movie_writer/mix_rate`, 48000 by default). */
export const MIX_RATE = 48000;
const VALUE_OPTIONS = ['scene', 'fps', 'out', 'stills', 'music', 'events', 'menu', 'godot-arg'];
const FLAG_OPTIONS = ['silent', 'reduced', 'no-switch', 'keep-frames', 'help'];

/** Reads the command line. `--name value` and `--name=value` both work. Throws an Error with a message for a wrong option. */
export function parseArgs(argv) {
  const out = { scene: 'session', fps: 30, out: '', stills: [], stillsText: [], music: '', events: '', menu: 0, silent: false, reduced: false, noSwitch: false, keepFrames: false, godotArgs: [], help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const raw = argv[i];
    if (!raw.startsWith('--')) throw new Error(`Unexpected argument: ${raw}`);
    let [name, value] = raw.slice(2).split(/=(.*)/s, 2);
    if (VALUE_OPTIONS.includes(name)) {
      if (value === undefined) { i += 1; value = argv[i]; }
      if (value === undefined) throw new Error(`--${name} needs a value`);
    } else if (!FLAG_OPTIONS.includes(name)) throw new Error(`Unknown option: --${name}`);
    switch (name) {
      case 'scene': out.scene = value; break;
      case 'fps': out.fps = Number(value); break;
      case 'out': out.out = value; break;
      case 'stills': out.stillsText = value.split(',').filter(Boolean); out.stills = out.stillsText.map(Number); break;
      case 'music': out.music = value; break;
      case 'events': out.events = value; break;
      case 'menu': out.menu = Number(value); break;
      case 'godot-arg': out.godotArgs.push(value); break;
      case 'silent': out.silent = true; break;
      case 'reduced': out.reduced = true; break;
      case 'no-switch': out.noSwitch = true; break;
      case 'keep-frames': out.keepFrames = true; break;
      case 'help': out.help = true; break;
      default: break;
    }
  }
  if (!SCENES.includes(out.scene)) throw new Error(`Unknown scene: ${out.scene} (use ${SCENES.join(', ')})`);
  if (!Number.isInteger(out.fps) || out.fps < 1 || out.fps > 240) throw new Error('--fps must be a whole number from 1 to 240');
  if (MIX_RATE % out.fps !== 0) throw new Error(`--fps must divide the audio mix rate of ${MIX_RATE} Hz (the engine takes a whole number of samples for each frame): use 24, 25, 30, 48 or 60`);
  if (out.stills.some((t) => !Number.isFinite(t) || t < 0)) throw new Error('--stills must be a list of seconds, for example 7,14.4,22.5');
  if (out.music && out.music !== 'off' && !TUNES.includes(out.music)) throw new Error(`--music must be one of ${TUNES.join(', ')}, off`);
  if (out.events && out.events !== '0' && out.events !== '1') throw new Error('--events must be 0 or 1');
  if (!Number.isFinite(out.menu) || out.menu < 0) throw new Error('--menu must be a number of seconds');
  return out;
}

/** The sound arguments of the client for the options of the recorder (the old mockup's `--silent`, `--music` and `--events`). */
export function soundArgs(opts) {
  const noEvents = opts.events === '0';
  let sound;
  if (opts.silent) sound = 'off';
  else if (opts.music === 'off') sound = noEvents ? 'off' : 'events';
  else sound = opts.music || 'krakowiak';
  const list = [`--sound=${sound}`];
  if (noEvents && sound !== 'off') list.push('--events=0');
  return { sound, list };
}

/** The file of the clip: out/<scene>[-<music>].mp4 in godot/out, unless --out says otherwise. */
export function outFile(opts) {
  if (opts.out) return path.resolve(opts.out);
  return path.join(DEFAULT_OUT_DIR, `${opts.scene}${opts.music ? `-${opts.music}` : ''}.mp4`);
}

/**
 * Makes the folder, and, when it lies inside the Godot project, puts an empty `.gdignore` file in it. Without that file Godot would
 * import every frame that a recording wrote the next time that it scans the project (thousands of PNG files).
 */
export function makeOutputFolder(dir) {
  mkdirSync(dir, { recursive: true });
  const inside = !path.relative(GODOT_DIR, dir).startsWith('..') && !path.isAbsolute(path.relative(GODOT_DIR, dir));
  if (inside) {
    // the .gdignore of the topmost folder under the project covers the folders below it
    const top = path.join(GODOT_DIR, path.relative(GODOT_DIR, dir).split(path.sep)[0]);
    if (top !== GODOT_DIR && !existsSync(path.join(top, '.gdignore'))) writeFileSync(path.join(top, '.gdignore'), '');
  }
}

/** The arguments of the client (after `--`) for one run. */
export function clientArgs(opts, extra = []) {
  const list = [`--demo=${opts.scene}`, `--record-fps=${opts.fps}`, ...soundArgs(opts).list];
  if (opts.reduced) list.push('--reduced-motion');
  if (opts.menu > 0) list.push(`--menu=${opts.menu}`);
  if (opts.noSwitch) list.push('--no-switch');
  return [...list, ...extra];
}

/** The ffmpeg arguments that make the clip from the frames (`frames` is the pattern of the PNG files) and the WAV file (or null). */
export function ffmpegArgs({ frames, wav, fps, out }) {
  return ['-y', '-loglevel', 'error', '-framerate', String(fps), '-i', frames, ...(wav ? ['-i', wav] : []),
    '-vf', 'scale=1920:1080:flags=neighbor', '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
    ...(wav ? ['-c:a', 'aac', '-b:a', '160k', '-shortest'] : []), '-movflags', '+faststart', out];
}

/** The lines that the client wrote that start with "[record]", as { scene, fps, frames, duration, conflicts: [...], done } . */
export function parseClientLog(text) {
  const result = { scene: null, fps: null, frames: null, duration: null, conflicts: [], done: false, conflictCount: 0 };
  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith('[record]')) continue;
    const head = /scene=(\S+) fps=(\d+) frames=(\d+) duration=([\d.]+)/.exec(line);
    if (head) Object.assign(result, { scene: head[1], fps: Number(head[2]), frames: Number(head[3]), duration: Number(head[4]) });
    const conflict = /^\[record\] conflict (.*)$/.exec(line);
    if (conflict) result.conflicts.push(conflict[1]);
    const done = /done frames=(\d+) conflicts=(\d+)/.exec(line);
    if (done) Object.assign(result, { done: true, framesWritten: Number(done[1]), conflictCount: Number(done[2]) });
  }
  return result;
}

/** Runs the client in Movie Maker and returns { code, log, info } when it ends. `movie` is the path of the first PNG file. */
export function runGodot({ godot = resolveGodot(), engineArgs, client, echo = true }) {
  return new Promise((resolve, reject) => {
    const child = spawn(godot, ['--path', GODOT_DIR, ...engineArgs, '--', ...client], { cwd: GODOT_DIR, stdio: ['ignore', 'pipe', 'pipe'] });
    let log = '';
    const take = (chunk) => { log += chunk.toString(); };
    child.stdout.on('data', take);
    child.stderr.on('data', take);
    child.on('error', reject);
    child.on('close', (code) => {
      if (echo) for (const line of log.split(/\r?\n/)) if (line.startsWith('[record]') || /SCRIPT ERROR|^ERROR: (?!.*still in use)/.test(line)) console.log(line);
      resolve({ code, log, info: parseClientLog(log) });
    });
  });
}

/** Makes the engine's arguments for a recording: the frames go to <dir>/f00000000.png and the sound to <dir>/f.wav. */
export function movieArgs(dir, fps, extra = []) {
  return ['--write-movie', path.join(dir, 'f.png'), '--fixed-fps', String(fps), ...extra];
}

/** Records the frames and the WAV into `dir`. Returns the run. Throws when the client fails or two penguins share a spot. */
export async function recordFrames(opts, dir) {
  makeOutputFolder(dir);
  const run = await runGodot({ engineArgs: movieArgs(dir, opts.fps, opts.godotArgs), client: clientArgs(opts) });
  const { info } = run;
  if (info.conflicts.length || info.conflictCount > 0) {
    throw new Error(`penguins share a spot:\n${info.conflicts.join('\n')}`);
  }
  if (run.code !== 0 || !info.done) throw new Error(`The client did not finish the recording (exit code ${run.code}). The last lines:\n${run.log.split(/\r?\n/).slice(-15).join('\n')}`);
  const written = readdirSync(dir).filter((name) => /^f\d{8}\.png$/.test(name)).length;
  if (written !== info.frames) throw new Error(`The client planned ${info.frames} frames and Godot wrote ${written}`);
  return { ...run, written, wav: path.join(dir, 'f.wav') };
}

/** Whether `ffmpeg` runs. */
export function findFfmpeg(env = process.env) {
  const command = env.FFMPEG || 'ffmpeg';
  const probe = spawnSync(command, ['-version'], { encoding: 'utf8' });
  if (probe.error || probe.status !== 0) return null;
  const encoders = spawnSync(command, ['-hide_banner', '-encoders'], { encoding: 'utf8' }).stdout ?? '';
  return { command, libx264: /libx264/.test(encoders), aac: /\baac\b/.test(encoders) };
}

function encode(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'inherit', 'inherit'] });
    child.on('error', reject);
    child.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited with ${code}`))));
  });
}

async function recordStills(opts) {
  const out = outFile(opts);
  const dir = path.dirname(out);
  makeOutputFolder(dir);
  const temp = path.join(dir, `.stills-${process.pid}`);
  makeOutputFolder(temp);
  try {
    const client = clientArgs(opts, [`--stills=${opts.stillsText.join(',')}`, `--stills-out=${temp}`]);
    const run = await runGodot({ engineArgs: ['--audio-driver', 'Dummy', ...opts.godotArgs], client });
    if (run.code !== 0) throw new Error(`The client failed (exit code ${run.code}). The last lines:\n${run.log.split(/\r?\n/).slice(-15).join('\n')}`);
    opts.stillsText.forEach((text, i) => {
      renameSync(path.join(temp, `still-${i}.png`), path.join(dir, `still-${opts.scene}-${text}.png`));
    });
    console.log(`wrote ${opts.stills.length} stills to ${dir}`);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log('See the top of tools/record.mjs.');
    return;
  }
  if (opts.stills.length) return recordStills(opts);
  const out = outFile(opts);
  makeOutputFolder(path.dirname(out));
  const dir = out.replace(/\.mp4$/, '') + '.frames';
  rmSync(dir, { recursive: true, force: true });
  const run = await recordFrames(opts, dir);
  const silent = soundArgs(opts).sound === 'off';
  const args = ffmpegArgs({ frames: path.join(dir, 'f%08d.png'), wav: silent ? null : run.wav, fps: opts.fps, out });
  const ffmpeg = findFfmpeg();
  if (!ffmpeg || !ffmpeg.libx264 || (!silent && !ffmpeg.aac)) {
    const commands = `ffmpeg ${args.map((a) => (/[\s]/.test(a) ? JSON.stringify(a) : a)).join(' ')}\n`;
    writeFileSync(`${out}.ffmpeg.txt`, commands);
    console.error(`${ffmpeg ? 'ffmpeg has no libx264 or no AAC encoder' : 'ffmpeg was not found on the PATH (set FFMPEG=<path> to use another)'}. The frames are in ${dir}.`);
    console.error(`The command that makes the clip is in ${out}.ffmpeg.txt:\n${commands}`);
    process.exitCode = 2;
    return;
  }
  await encode(ffmpeg.command, args);
  if (!opts.keepFrames) rmSync(dir, { recursive: true, force: true });
  console.log(`wrote ${out} (${run.written} frames, ${run.info.duration.toFixed(1)} s)`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exit(1); });
}
