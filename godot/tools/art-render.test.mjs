// Checks the image side of phase G-2:  node --test
//
// Without a browser it checks that the variant table, the art sources and the committed files agree:
//   * test/fixtures/art_variants.json has the table that variants.js gives now, and the hash of every source file;
//   * the PNG files have the hashes in MANIFEST.txt and the sizes that atlas_data.gd says.
// With CHROMIUM_PATH set (and Playwright and the fonts found, see render-art.mjs) it also renders the pictures again:
// two runs give the same bytes, and the pixels equal the committed files.
//
// The art sources in art/image_src/ started as copies of files of the JavaScript mockup (removed in phase G-10, see the
// git history). They are the only copy now, so no test compares them with the mockup.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { inflateSync } from 'node:zlib';
import {
  ANIMATIONS, CHARS, CORDS, FONTS, ICON_NAMES, POSES, PROP_PLACES, RUGS, SIGN_NAMES, WIDTH_STRINGS, frameName, penguinSpecs,
} from '../art/image_src/variants.js';
import { ART_DIR, FIXTURE_PATH, IMAGES_DIR, MANIFEST_PATH, manifestText, sourceHashes, tableFixture } from './render-art.mjs';

const fixture = () => JSON.parse(readFileSync(FIXTURE_PATH, 'utf8'));

test('the committed variant table is the table of variants.js', () => {
  const committed = fixture();
  assert.deepEqual(committed.table, JSON.parse(JSON.stringify(tableFixture())), 'run: node tools/render-art.mjs');
});

test('the committed fixture knows the hash of every source file, and no source file changed', () => {
  assert.deepEqual(fixture().sources, sourceHashes(), 'a source of the pictures changed: run node tools/render-art.mjs');
});

test('every picture name is unique, and the table is not empty', () => {
  const names = tableFixture().names;
  assert.equal(new Set(names).size, names.length);
  assert.ok(names.length > 600);
});

test('every penguin spec has a pose that the table lists, and no left view is baked', () => {
  for (const spec of penguinSpecs()) {
    assert.ok(!spec.name.includes('/left'), spec.name);
    if (spec.piece === 'full') {
      const [, , dir, pose] = spec.name.split('/');
      assert.ok(POSES[dir].includes(pose), `${spec.name}: the pose is in POSES.${dir}`);
    }
  }
});

test('every frame of every animation is a picture in the table', () => {
  const names = new Set(tableFixture().names);
  for (const [key, anim] of Object.entries(ANIMATIONS)) {
    for (const cord of Object.keys(CORDS)) {
      for (const pose of anim.poses) assert.ok(names.has(frameName(cord, anim, pose)), `${key}: ${cord} ${pose}`);
      if (anim.blink) for (const pose of anim.poses) assert.ok(names.has(frameName(cord, anim, pose, { blink: true })), `${key}: ${cord} ${pose} blink`);
    }
  }
});

test('the table has the glyph set, the rugs and the props that the plan names', () => {
  assert.equal(CHARS.length, 95 + 18 + 3);
  assert.equal(RUGS.length, 5);
  assert.equal(PROP_PLACES.length, 12);
  assert.equal(ICON_NAMES.length, 10);
  assert.equal(FONTS.length, 3);
  assert.ok(SIGN_NAMES.length > 5 && WIDTH_STRINGS.length > 20);
  assert.deepEqual(Object.keys(CORDS), ['claude-code', 'opencode', 'pi', 'hermes', 'default']);
});

// ---- the files

function decodePng(buffer) {
  assert.deepEqual([...buffer.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 'a PNG signature');
  let offset = 8, width = 0, height = 0;
  const idat = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset), type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') { width = data.readUInt32BE(0); height = data.readUInt32BE(4); assert.equal(data[8], 8); assert.equal(data[9], 6); }
    if (type === 'IDAT') idat.push(data);
    offset += 12 + length;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    assert.equal(raw[y * (width * 4 + 1)], 0, 'filter type 0: these files come from render-art.mjs');
    raw.copy(rgba, y * width * 4, y * (width * 4 + 1) + 1, (y + 1) * (width * 4 + 1));
  }
  return { width, height, rgba };
}

test('the PNG files have the hashes in MANIFEST.txt', () => {
  const lines = readFileSync(MANIFEST_PATH, 'utf8').split('\n').filter((l) => /^[0-9a-f]{64} {2}images\//.test(l));
  const files = readdirSync(IMAGES_DIR).filter((f) => f.endsWith('.png'));
  assert.equal(lines.length, files.length);
  for (const line of lines) {
    const [hash, name] = [line.slice(0, 64), line.slice(66)];
    assert.equal(createHash('sha256').update(readFileSync(join(ART_DIR, name))).digest('hex'), hash, name);
  }
});

test('atlas_data.gd and the PNG files agree on the sizes', () => {
  const text = readFileSync(join(ART_DIR, 'atlas_data.gd'), 'utf8');
  const sheets = JSON.parse(/const SHEETS: Array\[String\] = (\[.*\])/.exec(text)[1]);
  const sizes = sheets.map((path) => {
    const { width, height } = decodePng(readFileSync(join(ART_DIR, '..', path.replace('res://', ''))));
    return { width, height };
  });
  const body = /const PICTURES: Dictionary = \{\n([\s\S]*?)\n\}/.exec(text)[1].split('\n');
  assert.ok(body.length > 600);
  for (const line of body) {
    const [, name, sheet, x, y, w, h] = /^\t"(.*)": \[(\d+), (\d+), (\d+), (\d+), (\d+)\],$/.exec(line);
    const size = sizes[Number(sheet)];
    assert.ok(Number(x) + Number(w) <= size.width && Number(y) + Number(h) <= size.height, `${name} lies inside its sheet`);
  }
});

test('the manifest text of the tool keeps the lines of other folders', () => {
  const existing = `Copyright (c) 2026 Pawel Gorazda. All rights reserved.\n${'a'.repeat(64)}  sound/tune.wav\n${'b'.repeat(64)}  images/old.png\n`;
  const text = manifestText(new Map([['new.png', Buffer.from('x')]]), existing);
  assert.ok(text.includes('  sound/tune.wav\n'));
  assert.ok(text.includes('  images/new.png\n'));
  assert.ok(!text.includes('images/old.png'), 'the old image lines are replaced');
  assert.ok(text.startsWith('Copyright (c) 2026'));
});

// ---- a new render (needs a browser)

const browserReady = Boolean(process.env.CHROMIUM_PATH);

test('a new render gives the same bytes in two runs, and the pixels of the committed files', { skip: !browserReady && 'set CHROMIUM_PATH to run this', timeout: 180000 }, async (t) => {
  const { renderAll } = await import('./render-art.mjs');
  let results;
  try {
    results = await renderAll({ runs: 2 });
  } catch (err) {
    if (/Playwright was not found|fonts were not found/.test(err.message)) return t.skip(err.message);
    throw err;
  }
  const [first, second] = results;
  assert.deepEqual([...first.files.keys()], [...second.files.keys()]);
  for (const [name, bytes] of first.files) assert.ok(bytes.equals(second.files.get(name)), `${name}: the two runs differ`);
  assert.equal(first.atlasData, second.atlasData);
  assert.equal(first.fixture, second.fixture);
  for (const [name, bytes] of first.files) {
    const a = decodePng(bytes), b = decodePng(readFileSync(join(IMAGES_DIR, name)));
    assert.equal(a.width, b.width, name);
    assert.equal(a.height, b.height, name);
    assert.ok(a.rgba.equals(b.rgba), `${name}: the pixels differ from the committed file (run node tools/render-art.mjs)`);
  }
  assert.equal(first.atlasData, readFileSync(join(ART_DIR, 'atlas_data.gd'), 'utf8'));
  assert.equal(first.fixture, readFileSync(FIXTURE_PATH, 'utf8'));
});
