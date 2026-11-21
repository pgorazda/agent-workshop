// Copyright (c) 2026 Pawel Gorazda. All rights reserved.
// Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.
//
// The variant table: every picture that the Godot client may ask for. tools/render-art.mjs reads it, runs look.js
// in a browser for each entry, and packs the pictures into the files in art/images/.
//
// The first version comes from the poses and options that penguin(o) in look.js accepts, and from those that the
// scenes of the old JavaScript mockup used (removed, see the git history).
// The client may add entries: add them here, render again, and commit the new files.
//
// The left view is the right view, mirrored by the client (flip_h in Godot). So no picture is made for it.
//
// Names are paths with "/". A picture name is the same in this table, in the atlas data (art/atlas_data.gd) and in
// the client code. The order of the lists is the order in the files. Change it only on purpose: it changes every file.

/** The colour of the hat cord of each framework. The first four are the cord colours of the old JavaScript mockup. */
export const CORDS = {
  'claude-code': '#d97333',
  opencode: '#3380e6',
  pi: '#994dcc',
  hermes: '#e6bf33',
  // A framework that the table does not know gets this grey cord (P.gray in look.js).
  default: '#9aa6b5',
};

/**
 * The kilim rug colours, in the order of docs/arenas.md: red (arena A, and the single room), cobalt,
 * emerald, yellow, teal, then red again. `dark` is the colour of the ribbon and plate shade (RUGS in arenas-art.js).
 */
export const RUGS = [
  { name: 'red', color: '#d23c3c', dark: '#a82a32' },
  { name: 'cobalt', color: '#3a6fc4', dark: '#284f93' },
  { name: 'emerald', color: '#3f9a5a', dark: '#2c7343' },
  { name: 'yellow', color: '#d9a21b', dark: '#a87a10' },
  { name: 'teal', color: '#2a9d8f', dark: '#1e7469' },
];

/**
 * Poses for each direction. A pose is the `pose` option of penguin(o). The flipper switch of look.js is used for
 * "front" and "back", and a table of its own for "side", so the lists differ.
 * "front" and "back" show the face or the back. "side" looks to the right.
 */
export const POSES = {
  front: ['idle', 'walk', 'walk2', 'cheer', 'cheer2', 'wave', 'wave2', 'waveL', 'waveL2', 'think', 'flop'],
  side: ['idle', 'walk', 'walk2', 'browse', 'browse2', 'read', 'read2', 'shovel', 'shovel2', 'peer', 'tap', 'tap2', 'hammer', 'hammer2'],
  back: ['idle', 'walk', 'walk2', 'hammer', 'hammer2', 'think', 'cheer', 'cheer2', 'wave', 'wave2', 'waveL', 'waveL2'],
};

/** Poses that also have a picture with closed eyes (the `blink` option). Only where the eyes change the picture. */
export const BLINK_POSES = {
  front: ['idle', 'walk', 'walk2', 'wave', 'wave2', 'waveL', 'waveL2', 'think'],
  side: POSES.side,
  back: [],
};

/** The helper penguin is drawn at this scale (the `s` option). Only the poses that a helper uses have a picture. */
export const SMALL_SCALE = 0.72;
export const SMALL_POSES = {
  front: ['idle', 'walk', 'walk2', 'wave', 'wave2'],
  side: ['idle', 'walk', 'walk2', 'peer'],
  back: ['idle', 'walk', 'walk2'],
};

/** The picture names of one penguin variant. */
export function penguinName(cord, dir, pose, { blink = false, small = false, nocap = false } = {}) {
  return `penguin/${cord}/${dir}/${pose}${blink ? '/blink' : ''}${small ? '/small' : ''}${nocap ? '/nocap' : ''}`;
}

/**
 * Every penguin picture. Each entry: the name, the cord, the options of penguin(o), and the piece:
 * "full" (the whole sprite of 48x50 pixels, feet at x=24, y=46), "flop-body" (the flopped body, turned and cropped)
 * or "cap" (the cap alone, cropped).
 */
export function penguinSpecs() {
  const specs = [];
  for (const [cord, color] of Object.entries(CORDS)) {
    const add = (name, opts, piece = 'full') => specs.push({ name, sheet: `penguins_${cord}`, cord, opts: { ...opts, cord: color }, piece });
    for (const dir of ['front', 'side', 'back']) {
      for (const pose of POSES[dir]) add(penguinName(cord, dir, pose), { dir, pose });
      for (const pose of BLINK_POSES[dir]) add(penguinName(cord, dir, pose, { blink: true }), { dir, pose, blink: true });
      for (const pose of SMALL_POSES[dir]) add(penguinName(cord, dir, pose, { small: true }), { dir, pose, s: SMALL_SCALE });
    }
    // the cap flies off in a flop, and the penguin hops back with no cap
    add(penguinName(cord, 'front', 'idle', { nocap: true }), { dir: 'front', pose: 'idle', cap: false });
    add(`penguin/${cord}/flop-body`, { pose: 'flop', cap: false }, 'flop-body');
    add(`penguin/${cord}/cap`, { capOnly: true }, 'cap');
  }
  return specs;
}

/**
 * Where the old mockup put each prop (its table ST): `depth` is the sort key, `x` the centre
 * and `by` the bottom of the picture. The mockup draws a prop with drawAt(picture, x, by).
 * The sign post also has a small bitmap on its board at (264, 181), which the art code draws.
 */
export const PROP_PLACES = [
  { name: 'prop/workbench', build: 'workbench', depth: 78, x: 240, by: 78 },
  { name: 'prop/map-table', build: 'mapTable', depth: 84, x: 130, by: 84 },
  { name: 'prop/forge', build: 'forge', depth: 88, x: 396, by: 88 },
  { name: 'prop/coal-bucket', build: 'coalBucket', depth: 90, x: 427, by: 90 },
  { name: 'prop/shelf', build: 'shelf', depth: 124, x: 30, by: 124 },
  { name: 'prop/odd-jobs', build: 'oddJobs', depth: 178, x: 34, by: 178 },
  { name: 'prop/telescope', build: 'telescope', depth: 154, x: 448, by: 154 },
  { name: 'prop/helper-desk', build: 'helperDesk', depth: 212, x: 392, by: 212 },
  { name: 'prop/chair-back', build: 'chairBack', depth: 190, x: 90, by: 198 },
  { name: 'prop/chair-front', build: 'chairFront', depth: 208, x: 90, by: 210 },
  { name: 'prop/lamp', build: 'lamp', depth: 208, x: 124, by: 208 },
  { name: 'prop/sign-post', build: 'signPost', depth: 222, x: 266, by: 222 },
];

/** Props that the room or a scene draws in another way: the pieces of the wall, and the thought cloud with its candle. */
export const EXTRA_PROPS = [
  { name: 'prop/plant', build: 'plant' },
  { name: 'prop/pegboard', build: 'pegboard' },
  { name: 'prop/cloud', build: 'cloud' },
  { name: 'prop/cloud-mini', build: 'miniCloud' },
  ...[2, 3, 4, 5, 6, 7, 8].map((wax) => ({ name: `prop/candle/${wax}`, build: 'candle', arg: wax })),
];

/**
 * The app icon: the head and the cap of the penguin, on a rounded square, as one square picture. It is not part of an
 * atlas: the export presets use the file. "cells" is the size in art pixels and "scale" the size of one art pixel in
 * the file, so the file is cells * scale pixels wide. The window, the Windows .ico and the macOS .icns come from it.
 */
export const APP_ICON = {
  name: 'app-icon',
  file: 'app_icon.png',
  cells: 32,
  scale: 16,
  cord: 'hermes',
  // the window of the penguin sprite (48x50) that the icon shows, and where it lands in the icon
  from: { x: 11, y: 4, w: 26, h: 30 },
  at: { x: 3, y: 1 },
  background: '#24345e',
  corner: 5,
};

export const ICON_NAMES = ['read', 'search', 'write', 'exec', 'delegate', 'think', 'ask', 'star', 'web', 'other'];
/** SPARK in look.js, smallest to largest, and MINI_STAR. They are white: the client tints them. */
export const SPARK_COUNT = 4;
export const FLAME_COUNT = 4;

/** The pictures of the effects sheet, in order. */
export function effectSpecs() {
  return [
    ...ICON_NAMES.map((n) => ({ name: `icon/${n}`, build: 'icon', arg: n })),
    ...Array.from({ length: SPARK_COUNT }, (_, i) => ({ name: `spark/${i}`, build: 'spark', arg: i })),
    { name: 'spark/mini', build: 'miniStar' },
    ...Array.from({ length: FLAME_COUNT }, (_, i) => ({ name: `flame/${i}`, build: 'flame', arg: i })),
  ];
}

/** The pictures of the props sheet, in order. */
export function propSpecs() {
  return [...PROP_PLACES, ...EXTRA_PROPS].map(({ name, build, arg }) => ({ name, build, arg }));
}

/** One room of 480x232 pixels for each rug colour. The sign board has no text and no plate: the art code draws them. */
export function roomSpecs() {
  return RUGS.map((rug) => ({ name: `room/${rug.name}`, rug: rug.color }));
}

/** The pixel fonts. `family` is the font name that look.js asks for: "Tiny5" and "Silk" (Silkscreen). */
export const FONTS = [
  { id: 'tiny5-8', family: 'Tiny5', size: 8 },
  { id: 'silk-8', family: 'Silk', size: 8 },
  { id: 'silk-16', family: 'Silk', size: 16 },
];

/**
 * The characters of the glyph atlas, for every font: printable ASCII, the Polish letters, the middle dot that the
 * mockup uses in the bar, and the two arrows of the latin subset of the fonts. Another character shows as "?".
 */
export const POLISH = 'ĄĆĘŁŃÓŚŹŻąćęłńóśźż';
export const EXTRA_CHARS = '·↑↓';
export const CHARS = Array.from({ length: 95 }, (_, i) => String.fromCharCode(32 + i)).join('') + POLISH + EXTRA_CHARS;

/** Texts whose width the mockup measures with textW(). The tests compare the width that the atlas gives. */
export const WIDTH_STRINGS = [
  'AGENT WORKSHOP', 'ARENA', 'SESSION START', 'TURN COMPLETE!', 'APPROVAL NEEDED', 'APPROVED', 'FOLLOW', 'SOUND',
  'claude-code joined', 'claude-code', 'Turn complete', 'waiting for agent activity', 'waiting for agents', 'connecting', 'online',
  'git push origin HEAD', 'answer in your terminal', 'approved in your terminal', 'Glob', 'Read', 'Edit', 'Task', 'Bash',
  'exit 1', 'focus: claude-code 12', '12 agents · 3 helpers · 41 calls', 'calls 12', 'helpers 2', 'OK', 'WAIT', 'FAIL', 'DONE',
  '0123456789', 'The quick brown fox jumps over the lazy dog', 'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG',
  'Zażółć gęślą jaźń', 'ZAŻÓŁĆ GĘŚLĄ JAŹŃ', 'góralski', '↑ ↓', '?', ' ',
];

/** The names that the sign layout is checked for: single letters of every width, and double letters. */
export const SIGN_NAMES = ['A', 'B', 'E', 'I', 'M', 'W', 'Z', 'AA', 'AI', 'IE', 'MM', 'WW', 'ZZ'];

/**
 * Animations: the frames that the mockup plays for each activity. A frame is a pose; the picture name is
 * penguin/<cord>/<dir>/<pose> (with /small for a helper). `period` is the time of one frame in seconds.
 * `flip` is true when the mockup mirrors the picture. The names of the activities come from the old mockup.
 */
export const ANIMATIONS = {
  'walk/front': { dir: 'front', poses: ['walk', 'walk2'], period: 0.13 },
  'walk/side': { dir: 'side', poses: ['walk', 'walk2'], period: 0.13 },
  'walk/back': { dir: 'back', poses: ['walk', 'walk2'], period: 0.13 },
  'idle/front': { dir: 'front', poses: ['idle'], period: 1, blink: true },
  'idle/side': { dir: 'side', poses: ['idle'], period: 1, blink: true },
  search: { dir: 'side', poses: ['browse', 'browse2'], period: 0.3 },
  read: { dir: 'side', poses: ['read', 'read', 'read2'], period: 0.22, flip: true },
  write: { dir: 'back', poses: ['hammer', 'hammer2'], period: 0.22 },
  exec: { dir: 'side', poses: ['shovel2', 'shovel'], period: 0.32 },
  build: { dir: 'back', poses: ['hammer', 'hammer2'], period: 0.24 },
  web: { dir: 'side', poses: ['peer'], period: 1 },
  other: { dir: 'side', poses: ['hammer', 'hammer2'], period: 0.24, flip: true },
  delegate: { dir: 'side', poses: ['tap', 'tap2'], period: 0.18 },
  wait: { dir: 'front', poses: ['waveL', 'waveL2'], period: 0.3 },
  approve: { dir: 'front', poses: ['cheer'], period: 1 },
  cheer: { dir: 'front', poses: ['cheer', 'cheer2'], period: 0.275 },
  think: { dir: 'front', poses: ['think'], period: 1 },
  queue: { dir: 'side', poses: ['idle'], period: 1, blink: true },
  'helper/wave': { dir: 'front', poses: ['wave', 'wave2'], period: 0.2, small: true },
  'helper/walk': { dir: 'side', poses: ['walk', 'walk2'], period: 0.13, small: true },
  'helper/peer': { dir: 'side', poses: ['peer'], period: 1, small: true },
};

/** The picture name of a frame of an animation, for one cord. */
export function frameName(cord, anim, pose, { blink = false } = {}) {
  return penguinName(cord, anim.dir, pose, { blink, small: Boolean(anim.small) });
}
