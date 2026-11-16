// Tests of the helpers of tools/record.mjs and tools/determinism.mjs (phase G-8). They need neither a window nor ffmpeg. The recording
// itself is run by hand (see godot/README.md, "Phase G-8").

import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { GODOT_DIR } from './godot-path.mjs';
import { DEFAULT_OUT_DIR, SCENES, clientArgs, ffmpegArgs, findFfmpeg, makeOutputFolder, movieArgs, outFile, parseArgs, parseClientLog, soundArgs } from './record.mjs';
import { compareHashes } from './determinism.mjs';

test('the scenes of the recorder are the scenes of the demo files', () => {
  const demo = readdirSync(path.join(GODOT_DIR, 'demo')).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5));
  assert.deepEqual([...SCENES].sort(), demo.sort());
});

test('the defaults are the mockup recorder defaults: session, 30 fps, krakowiak and the event sounds', () => {
  const opts = parseArgs([]);
  assert.equal(opts.scene, 'session');
  assert.equal(opts.fps, 30);
  assert.deepEqual(clientArgs(opts), ['--demo=session', '--record-fps=30', '--sound=krakowiak']);
  assert.equal(outFile(opts), path.join(DEFAULT_OUT_DIR, 'session.mp4'));
});

test('options come as --name value or --name=value', () => {
  const a = parseArgs(['--scene', 'multi', '--fps', '60', '--stills', '7,14.4,22.5', '--music', 'oberek', '--menu', '3']);
  const b = parseArgs(['--scene=multi', '--fps=60', '--stills=7,14.4,22.5', '--music=oberek', '--menu=3']);
  assert.deepEqual(a, b);
  assert.deepEqual(a.stills, [7, 14.4, 22.5]);
  assert.deepEqual(a.stillsText, ['7', '14.4', '22.5']);
  assert.equal(outFile(a), path.join(DEFAULT_OUT_DIR, 'multi-oberek.mp4'), 'the music is in the name, as in the mockup recorder');
});

test('the sound options give the sound of the client', () => {
  assert.deepEqual(soundArgs(parseArgs([])).list, ['--sound=krakowiak']);
  assert.deepEqual(soundArgs(parseArgs(['--music', 'kujawiak'])).list, ['--sound=kujawiak']);
  assert.deepEqual(soundArgs(parseArgs(['--music', 'off'])).list, ['--sound=events'], 'no music: only the event sounds');
  assert.deepEqual(soundArgs(parseArgs(['--events', '0'])).list, ['--sound=krakowiak', '--events=0'], 'the tune without the event sounds');
  assert.deepEqual(soundArgs(parseArgs(['--music', 'off', '--events', '0'])).list, ['--sound=off']);
  assert.deepEqual(soundArgs(parseArgs(['--silent'])).list, ['--sound=off']);
  assert.equal(soundArgs(parseArgs(['--silent', '--music', 'oberek'])).sound, 'off', '--silent wins');
});

test('the other options go to the client', () => {
  const opts = parseArgs(['--scene', 'follow', '--reduced', '--menu', '2.5', '--no-switch', '--fps', '24']);
  assert.deepEqual(clientArgs(opts), ['--demo=follow', '--record-fps=24', '--sound=krakowiak', '--reduced-motion', '--menu=2.5', '--no-switch']);
  assert.deepEqual(clientArgs(opts, ['--stills=3']).slice(-1), ['--stills=3']);
});

test('a wrong option is an error that says what is wrong', () => {
  assert.throws(() => parseArgs(['--scene', 'nothing']), /Unknown scene: nothing/);
  assert.throws(() => parseArgs(['--fps', '0']), /--fps/);
  assert.throws(() => parseArgs(['--fps', '2.5']), /--fps/);
  assert.throws(() => parseArgs(['--fps', '29']), /divide the audio mix rate/);
  for (const fps of [24, 25, 30, 48, 60]) assert.equal(parseArgs(['--fps', String(fps)]).fps, fps);
  assert.throws(() => parseArgs(['--stills', '3,x']), /--stills/);
  assert.throws(() => parseArgs(['--music', 'polka']), /--music/);
  assert.throws(() => parseArgs(['--events', '2']), /--events/);
  assert.throws(() => parseArgs(['--bogus']), /Unknown option/);
  assert.throws(() => parseArgs(['stray']), /Unexpected argument/);
  assert.throws(() => parseArgs(['--scene']), /needs a value/);
});

test('the engine is told the frame rate twice: --fixed-fps and --record-fps, and the frames go to f<number>.png', () => {
  const args = movieArgs(path.join('some', 'dir'), 30);
  assert.equal(args[0], '--write-movie');
  assert.equal(args[1], path.join('some', 'dir', 'f.png'));
  assert.deepEqual(args.slice(2), ['--fixed-fps', '30']);
  assert.ok(clientArgs(parseArgs(['--fps', '30'])).includes('--record-fps=30'));
});

test('ffmpeg makes 1920x1080 with a 4x integer scale and no smoothing, libx264 and AAC', () => {
  const args = ffmpegArgs({ frames: 'frames/f%08d.png', wav: 'frames/f.wav', fps: 30, out: 'clip.mp4' });
  const joined = args.join(' ');
  assert.match(joined, /-framerate 30 -i frames\/f%08d\.png -i frames\/f\.wav/);
  assert.match(joined, /scale=1920:1080:flags=neighbor/);
  assert.match(joined, /-c:v libx264/);
  assert.match(joined, /-c:a aac/);
  assert.equal(args.at(-1), 'clip.mp4');
  assert.ok(!ffmpegArgs({ frames: 'f%08d.png', wav: null, fps: 30, out: 'x.mp4' }).includes('aac'), 'no sound track for a silent clip');
  assert.equal(1920 / 480, 4);
  assert.equal(1080 / 270, 4);
});

test('the log of the client gives the frames, the duration and the conflicts', () => {
  const log = [
    'Godot Engine v4.7.2', '[record] scene=tour fps=30 frames=8460 duration=281.975',
    '[record] conflict t=12.30 arena A: a and b stand on one spot at (366, 93)', 'other text',
    '[record] done frames=8460 conflicts=14',
  ].join('\r\n');
  const info = parseClientLog(log);
  assert.equal(info.scene, 'tour');
  assert.equal(info.frames, 8460);
  assert.equal(info.fps, 30);
  assert.equal(info.duration, 281.975);
  assert.equal(info.conflicts.length, 1);
  assert.equal(info.conflictCount, 14);
  assert.ok(info.done);
  assert.equal(parseClientLog('nothing').done, false);
});

test('ffmpeg is looked for with FFMPEG or on the PATH, and a missing one is null', () => {
  assert.equal(findFfmpeg({ FFMPEG: path.join('no', 'such', 'ffmpeg') }), null);
});

test('two runs are the same when every frame and the sound agree', () => {
  const a = { frames: ['1', '2', '3'], wav: 'w' };
  assert.equal(compareHashes(a, { frames: ['1', '2', '3'], wav: 'w' }).same, true);
  const other = compareHashes(a, { frames: ['1', 'x', '3'], wav: 'w' });
  assert.equal(other.same, false);
  assert.deepEqual(other.differing, [1]);
  assert.equal(compareHashes(a, { frames: ['1', '2', '3'], wav: 'v' }).wavEqual, false);
  assert.equal(compareHashes(a, { frames: ['1', '2'], wav: 'w' }).same, false, 'a missing frame');
});

test('a folder of frames inside the project gets a .gdignore, so that Godot does not import the frames', () => {
  const inside = path.join(DEFAULT_OUT_DIR, `.test-${process.pid}`, 'frames');
  try {
    makeOutputFolder(inside);
    assert.ok(existsSync(path.join(DEFAULT_OUT_DIR, '.gdignore')), 'the .gdignore of out/ covers the folders below it');
    assert.ok(existsSync(inside));
  } finally {
    rmSync(path.join(DEFAULT_OUT_DIR, `.test-${process.pid}`), { recursive: true, force: true });
  }
  const outside = mkdtempSync(path.join(tmpdir(), 'agent-workshop-out-'));
  try {
    makeOutputFolder(path.join(outside, 'clips'));
    assert.ok(!existsSync(path.join(outside, 'clips', '.gdignore')) && !existsSync(path.join(outside, '.gdignore')), 'a folder outside the project gets none');
  } finally {
    rmSync(outside, { recursive: true, force: true });
  }
  assert.ok(GODOT_DIR.length > 0);
});
