// Renders the pictures of the Godot client: runs the art code in art/image_src/ in headless Chromium and saves PNG files.
//
//   node tools/render-art.mjs            write godot/art/images/*.png, art/atlas_data.gd, art/MANIFEST.txt (its images/
//                                        lines) and test/fixtures/art_variants.json
//   node tools/render-art.mjs --check    render twice, compare the two runs with each other and with the files on disk,
//                                        and write nothing. It exits with code 1 when something differs.
//
// What it does
//   1. It loads art/image_src/base.js, look.js, effects_src.js and bake.js into one page, with the pixel fonts.
//   2. bake.js draws every picture of the variant table (art/image_src/variants.js) with the code of look.js.
//   3. This tool packs the pictures into sheets in the order of the table, encodes the PNG files itself, and writes the
//      atlas data. Nothing here depends on the time or on random numbers, so a second run gives the same bytes.
//
// What you need
//   * Playwright, found in PLAYWRIGHT_DIR (a folder with node_modules) or in godot/.
//     Do not add it to a package.json: "npm install --no-save playwright" in one of those folders is enough.
//   * CHROMIUM_PATH: a Chrome or Chromium that you have.
//   * The two fonts from npm (@fontsource/tiny5 and @fontsource/silkscreen, version 5.3.0): FONTSOURCE_DIR, or godot/node_modules
//     ("npm install --no-save @fontsource/tiny5@5.3.0 @fontsource/silkscreen@5.3.0" in godot/). The fonts are not part of this repository.
//
// The PNG files are encoded here, not by the browser, so that a new browser version does not change them. The zlib of
// Node gives the same bytes for the same Node version. A different Node version may give other bytes of the same
// pictures: then `--check` fails on the hashes only, and the pictures are the same.

import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import {
  ANIMATIONS, APP_ICON, CHARS, CORDS, FLAME_COUNT, FONTS, ICON_NAMES, POLISH, PROP_PLACES, RUGS, SIGN_NAMES, SPARK_COUNT,
  WIDTH_STRINGS, effectSpecs, frameName, penguinSpecs, propSpecs, roomSpecs,
} from '../art/image_src/variants.js';

const GODOT_DIR = fileURLToPath(new URL('..', import.meta.url));
const REPO_DIR = join(GODOT_DIR, '..');
export const ART_DIR = join(GODOT_DIR, 'art');
export const IMAGES_DIR = join(ART_DIR, 'images');
export const SRC_DIR = join(ART_DIR, 'image_src');
export const FIXTURE_PATH = join(GODOT_DIR, 'test', 'fixtures', 'art_variants.json');
export const ATLAS_DATA_PATH = join(ART_DIR, 'atlas_data.gd');
export const MANIFEST_PATH = join(ART_DIR, 'MANIFEST.txt');

/** The files of the baker page, in the order in which they load. */
export const PAGE_SCRIPTS = ['base.js', 'look.js', 'effects_src.js', 'bake.js'];

const GD_HEADER = [
  '# Copyright (c) 2026 Pawel Gorazda. All rights reserved.',
  '# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.',
];
const MANIFEST_FIRST_LINE = 'Copyright (c) 2026 Pawel Gorazda. All rights reserved.';
const GUTTER = 1; // transparent pixels between two pictures in a sheet
const SHEET_WIDTHS = { props: 320, effects: 128, glyphs: 256 };
const PENGUIN_SHEET_WIDTH = 512;

// ---------------------------------------------------------------- the table as data

/** The part of the table that tests read. It needs no browser. */
export function tableFixture() {
  const names = [...penguinSpecs(), ...propSpecs(), ...effectSpecs(), ...roomSpecs()].map((s) => s.name);
  const glyphNames = FONTS.flatMap((f) => [...CHARS].map((ch) => glyphName(f.id, ch)));
  const animations = {};
  for (const [key, anim] of Object.entries(ANIMATIONS)) {
    animations[key] = {
      dir: anim.dir,
      small: Boolean(anim.small),
      frames: Object.keys(CORDS).map((cord) => ({ cord, names: anim.poses.map((pose) => frameName(cord, anim, pose)) })),
      blink: anim.blink ? Object.keys(CORDS).map((cord) => ({ cord, names: anim.poses.map((pose) => frameName(cord, anim, pose, { blink: true })) })) : [],
    };
  }
  return {
    names: [...names, ...glyphNames],
    animations,
    cords: CORDS,
    rugs: RUGS,
    chars: CHARS,
    polish: POLISH,
    fonts: FONTS,
    appIcon: APP_ICON,
  };
}

/** The name of a glyph picture, for example "glyph/silk-8/U+0041". */
export function glyphName(fontId, ch) {
  return `glyph/${fontId}/U+${ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0')}`;
}

/** SHA-256 of a source file, with line ends counted as LF. */
function sourceHash(path) {
  return createHash('sha256').update(readFileSync(path, 'utf8').split('\r\n').join('\n')).digest('hex');
}

/** The hashes of the files that the pictures depend on. A test fails when one of them changes and the pictures do not. */
export function sourceHashes() {
  const out = {};
  for (const file of [...PAGE_SCRIPTS, 'variants.js']) out[`art/image_src/${file}`] = sourceHash(join(SRC_DIR, file));
  return out;
}

// ---------------------------------------------------------------- PNG

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

/** A PNG file of 8-bit RGBA pixels. Fixed filter, fixed compression level: the same pixels give the same bytes. */
export function encodePng(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // colour type: RGBA
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0; // filter: none
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9, memLevel: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------------------------------------------------------------- packing

/** Puts the pictures in a sheet, left to right in rows, in the given order. */
function packSheet(items, width) {
  const placed = [];
  let x = GUTTER, y = GUTTER, rowH = 0;
  for (const item of items) {
    if (item.w + 2 * GUTTER > width) throw new Error(`${item.name} is wider than its sheet`);
    if (x + item.w + GUTTER > width) { x = GUTTER; y += rowH + GUTTER; rowH = 0; }
    placed.push({ ...item, x, y });
    x += item.w + GUTTER;
    rowH = Math.max(rowH, item.h);
  }
  const height = y + rowH + GUTTER;
  const rgba = Buffer.alloc(width * height * 4);
  for (const p of placed) {
    for (let row = 0; row < p.h; row++) p.rgba.copy(rgba, ((p.y + row) * width + p.x) * 4, row * p.w * 4, (row + 1) * p.w * 4);
  }
  return { width, height, rgba, placed };
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

function fontsourceDir() {
  const roots = [process.env.FONTSOURCE_DIR, join(GODOT_DIR, 'node_modules', '@fontsource')].filter(Boolean);
  for (const root of roots) if (existsSync(join(root, 'tiny5', 'files')) && existsSync(join(root, 'silkscreen', 'files'))) return root;
  throw new Error(`The fonts were not found. Run "npm install --no-save @fontsource/tiny5@5.3.0 @fontsource/silkscreen@5.3.0" in godot/, or set FONTSOURCE_DIR. Looked in: ${roots.join(', ')}`);
}

/** @font-face rules with the font files inline. Silkscreen gets the name "Silk", as in the old mockup page. */
function fontCss() {
  const root = fontsourceDir();
  const rules = [];
  for (const [family, dir, base] of [['Tiny5', 'tiny5', 'tiny5'], ['Silk', 'silkscreen', 'silkscreen']]) {
    const ranges = JSON.parse(readFileSync(join(root, dir, 'unicode.json'), 'utf8'));
    for (const subset of ['latin', 'latin-ext']) {
      const data = readFileSync(join(root, dir, 'files', `${base}-${subset}-400-normal.woff2`)).toString('base64');
      rules.push(`@font-face{font-family:${family};src:url(data:font/woff2;base64,${data}) format('woff2');unicode-range:${ranges[subset]}}`);
    }
  }
  return rules.join('\n');
}

function bakeSpec() {
  return {
    penguins: penguinSpecs(),
    props: propSpecs(),
    effects: effectSpecs(),
    rooms: roomSpecs(),
    appIcon: { ...APP_ICON, cordColor: CORDS[APP_ICON.cord] },
    fonts: FONTS,
    chars: CHARS,
    widthStrings: WIDTH_STRINGS,
    signNames: SIGN_NAMES,
    iconNames: ICON_NAMES,
    sparkCount: SPARK_COUNT,
    flameCount: FLAME_COUNT,
  };
}

/** Runs the baker page once. Returns what bake.js gave back, and the browser version. */
async function bakeOnce(browser) {
  const page = await browser.newPage();
  try {
    const errors = [];
    page.on('pageerror', (err) => errors.push(err.message));
    await page.setContent(`<!doctype html><meta charset="utf-8"><style>${fontCss()}</style><canvas id="c" width="480" height="270"></canvas>`);
    for (const file of PAGE_SCRIPTS) await page.addScriptTag({ content: readFileSync(join(SRC_DIR, file), 'utf8') });
    if (errors.length) throw new Error(`page errors: ${errors.join('; ')}`);
    return await page.evaluate((spec) => bakeAll(spec), bakeSpec());
  } finally {
    await page.close();
  }
}

// ---------------------------------------------------------------- the output

const fromBase64 = (text) => Buffer.from(text, 'base64');

/** Packs the pictures that the browser gave and builds every output file in memory. */
export function buildOutputs(baked) {
  const byName = new Map(baked.sprites.map((s) => [s.name, { ...s, rgba: fromBase64(s.rgba) }]));
  const take = (name) => {
    const item = byName.get(name);
    if (!item) throw new Error(`the baker gave no picture named ${name}`);
    byName.delete(name);
    return item;
  };

  const sheets = []; // { file, packed }
  for (const cord of Object.keys(CORDS)) {
    const items = penguinSpecs().filter((s) => s.cord === cord).map((s) => take(s.name));
    sheets.push({ file: `penguins_${cord}.png`, packed: packSheet(items, PENGUIN_SHEET_WIDTH) });
  }
  sheets.push({ file: 'props.png', packed: packSheet(propSpecs().map((s) => take(s.name)), SHEET_WIDTHS.props) });
  sheets.push({ file: 'effects.png', packed: packSheet(effectSpecs().map((s) => take(s.name)), SHEET_WIDTHS.effects) });
  const appIcon = take(APP_ICON.name); // not in an atlas: the export presets use the file

  const glyphItems = [];
  const fontData = {};
  for (const font of baked.fonts) {
    fontData[font.id] = { oy: font.oy, h: font.h };
    for (const gl of font.glyphs) glyphItems.push({ name: glyphName(font.id, gl.ch), w: gl.adv, h: font.h, rgba: fromBase64(gl.rgba) });
  }
  sheets.push({ file: 'glyphs.png', packed: packSheet(glyphItems, SHEET_WIDTHS.glyphs) });

  const pictures = []; // [name, sheetIndex, x, y, w, h]
  sheets.forEach((sheet, index) => sheet.packed.placed.forEach((p) => pictures.push([p.name, index, p.x, p.y, p.w, p.h])));
  for (const room of roomSpecs()) {
    const item = take(room.name);
    sheets.push({ file: `room_${room.name.slice('room/'.length)}.png`, packed: { width: item.w, height: item.h, rgba: item.rgba, placed: [] } });
    pictures.push([room.name, sheets.length - 1, 0, 0, item.w, item.h]);
  }
  if (byName.size) throw new Error(`pictures that no sheet took: ${[...byName.keys()].join(', ')}`);

  const files = new Map();
  files.set(APP_ICON.file, encodePng(appIcon.w, appIcon.h, appIcon.rgba));
  for (const sheet of sheets) files.set(sheet.file, encodePng(sheet.packed.width, sheet.packed.height, sheet.packed.rgba));

  return {
    files,
    sheets: sheets.map((s) => ({ file: s.file, width: s.packed.width, height: s.packed.height })),
    atlasData: atlasDataText(sheets, pictures, fontData),
    fixture: fixtureText(baked),
    notes: baked.notes,
    checked: baked.checked,
  };
}

// ---- GDScript text

function gd(value, indent = '') {
  if (value === null) return 'null';
  if (typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) return `[${value.map((v) => gd(v, indent)).join(', ')}]`;
  const entries = Object.entries(value);
  if (!entries.length) return '{}';
  const inner = `${indent}\t`;
  return `{\n${entries.map(([k, v]) => `${inner}${JSON.stringify(k)}: ${gd(v, inner)},`).join('\n')}\n${indent}}`;
}

function atlasDataText(sheets, pictures, fontData) {
  const animations = {};
  for (const [key, a] of Object.entries(ANIMATIONS)) {
    animations[key] = { dir: a.dir, poses: a.poses, period: a.period, flip: Boolean(a.flip), blink: Boolean(a.blink), small: Boolean(a.small) };
  }
  const places = PROP_PLACES.map(({ name, depth, x, by }) => ({ name, depth, x, by }));
  const lines = [
    ...GD_HEADER,
    '#',
    '# Made by godot/tools/render-art.mjs. Do not edit by hand: change art/image_src/variants.js and render again.',
    'extends RefCounted',
    '## The name and the rectangle of every picture in the files of art/images/.',
    '',
    '## The image files. A picture lies in one of them. Rooms have a file each: one picture of 480x232 pixels.',
    `const SHEETS: Array[String] = ${gd(sheets.map((s) => `res://art/images/${s.file}`))}`,
    '',
    '## name -> [sheet index, x, y, width, height]. The order of the sheets and of the names is fixed.',
    'const PICTURES: Dictionary = {',
    ...pictures.map(([name, ...rect]) => `\t${JSON.stringify(name)}: ${gd(rect)},`),
    '}',
    '',
    '## The pixel fonts. The glyph cells of a font are as high as `h`. A glyph is drawn `oy` pixels below the line top.',
    `const GLYPH_FONTS: Dictionary = ${gd(fontData)}`,
    '',
    '## Shown for a character that has no glyph.',
    'const UNKNOWN_CHAR: String = "?"',
    '',
    '## Hat cord colours by framework, as HTML colour codes. "default" is for a framework that is not listed.',
    `const CORDS: Dictionary = ${gd(CORDS)}`,
    '',
    '## Kilim rug colours in the order of the arenas (arena A is the first, arena F the first again). "dark" shades ribbons.',
    `const RUGS: Array[Dictionary] = ${gd(RUGS)}`,
    '',
    '## Where each prop goes in the room: depth (sort key), the centre x and the bottom y of the picture.',
    `const PROP_PLACES: Array[Dictionary] = ${gd(places)}`,
    '',
    '## The frames of each activity: the poses in order and the time of one frame in seconds. See variants.js.',
    `const ANIMATIONS: Dictionary = ${gd(animations)}`,
    '',
  ];
  return lines.join('\n');
}

function fixtureText(baked) {
  const fixture = {
    note: 'Made by godot/tools/render-art.mjs. Do not edit by hand. "table" is what the client may ask for; the rest is what the browser measured.',
    sources: sourceHashes(),
    table: tableFixture(),
    widths: baked.widths,
    signs: baked.signs,
  };
  return `${JSON.stringify(fixture, null, 1)}\n`;
}

/** The lines of the manifest for the image files, merged with the lines of other folders that are already there. */
export function manifestText(files, existing = '') {
  const lines = new Map();
  for (const line of existing.split('\n')) {
    const match = /^([0-9a-f]{64}) {2}(\S.*)$/.exec(line);
    if (match && !match[2].startsWith('images/')) lines.set(match[2], match[1]);
  }
  for (const [file, bytes] of files) lines.set(`images/${file}`, createHash('sha256').update(bytes).digest('hex'));
  const sorted = [...lines.keys()].sort();
  return `${[MANIFEST_FIRST_LINE, ...sorted.map((name) => `${lines.get(name)}  ${name}`)].join('\n')}\n`;
}

// ---------------------------------------------------------------- main

/** Renders in a fresh browser. */
export async function renderAll({ runs = 1 } = {}) {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
  try {
    const results = [];
    for (let i = 0; i < runs; i++) results.push(buildOutputs(await bakeOnce(browser)));
    return results;
  } finally {
    await browser.close();
  }
}

function diff(a, b) {
  const problems = [];
  for (const name of new Set([...a.files.keys(), ...b.files.keys()])) {
    if (!a.files.has(name) || !b.files.has(name)) problems.push(`${name}: only one side has it`);
    else if (!a.files.get(name).equals(b.files.get(name))) problems.push(`${name}: the bytes differ`);
  }
  if (a.atlasData !== b.atlasData) problems.push('atlas_data.gd differs');
  if (a.fixture !== b.fixture) problems.push('art_variants.json differs');
  return problems;
}

function readIfThere(path) {
  return existsSync(path) ? readFileSync(path) : null;
}

function main() {
  const check = process.argv.includes('--check');
  return renderAll({ runs: 2 }).then(([first, second]) => {
    for (const note of first.notes) console.log(`note: ${note}`);
    const c = first.checked;
    console.log(`checked in the page: ${c.signs} signs (baked room plus sign equals room()), ${c.texts} texts (every glyph pixel is in the output of text()), ${c.extraPixels} pixels that text() adds between letters, ${c.textsNotChecked.length} texts too long for text()`);
    const problems = diff(first, second).map((p) => `two runs differ: ${p}`);
    const total = [...first.files.values()].reduce((sum, b) => sum + b.length, 0);
    console.log(`${first.files.size} image files, ${total} bytes; sheets: ${first.sheets.map((s) => `${s.file} ${s.width}x${s.height}`).join(', ')}`);
    if (check) {
      for (const [name, bytes] of first.files) {
        const onDisk = readIfThere(join(IMAGES_DIR, name));
        if (!onDisk || !onDisk.equals(bytes)) problems.push(`images/${name} is not the rendered file`);
      }
      const atlas = readIfThere(ATLAS_DATA_PATH);
      if (!atlas || atlas.toString('utf8') !== first.atlasData) problems.push('art/atlas_data.gd is not the rendered file');
      const fixture = readIfThere(FIXTURE_PATH);
      if (!fixture || fixture.toString('utf8') !== first.fixture) problems.push('test/fixtures/art_variants.json is not the rendered file');
      const manifest = readIfThere(MANIFEST_PATH)?.toString('utf8') ?? '';
      if (manifest !== manifestText(first.files, manifest)) problems.push('art/MANIFEST.txt does not list the rendered images');
      if (problems.length) {
        for (const p of problems) console.error(`FAIL: ${p}`);
        return 1;
      }
      console.log('check passed: two runs give the same files, and they are the files on disk');
      return 0;
    }
    if (problems.length) {
      for (const p of problems) console.error(`FAIL: ${p}`);
      return 1;
    }
    mkdirSync(IMAGES_DIR, { recursive: true });
    for (const entry of readdirSync(IMAGES_DIR)) {
      if (entry.endsWith('.png') && !first.files.has(entry)) {
        rmSync(join(IMAGES_DIR, entry));
        rmSync(join(IMAGES_DIR, `${entry}.import`), { force: true });
      }
    }
    for (const [name, bytes] of first.files) writeFileSync(join(IMAGES_DIR, name), bytes);
    writeFileSync(ATLAS_DATA_PATH, first.atlasData);
    mkdirSync(join(GODOT_DIR, 'test', 'fixtures'), { recursive: true });
    writeFileSync(FIXTURE_PATH, first.fixture);
    writeFileSync(MANIFEST_PATH, manifestText(first.files, readIfThere(MANIFEST_PATH)?.toString('utf8') ?? ''));
    console.log('written: art/images/*.png, art/atlas_data.gd, art/MANIFEST.txt, test/fixtures/art_variants.json');
    return 0;
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().then(
    (code) => { process.exitCode = code; },
    (err) => { console.error(`error: ${err.stack ?? err.message}`); process.exitCode = 1; },
  );
}
