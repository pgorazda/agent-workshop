// Checks the split between the MIT code and the art (see LICENSE-ASSETS):  node --test
//
// The rules are in license-check.mjs. This file runs them on the real tree. It also runs them on small
// made-up trees, to show that each rule can fail.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GD_HEADER, JS_HEADER, MANIFEST_FIRST_LINE, checkLicense } from './license-check.mjs';

const REPO = fileURLToPath(new URL('../../', import.meta.url));

test('the repository passes the license check', () => {
  assert.deepEqual(checkLicense(REPO), []);
});

test('godot/art/ holds at least one file with the header (the check has something to find)', async () => {
  const { readdirSync, readFileSync } = await import('node:fs');
  const files = readdirSync(join(REPO, 'godot', 'art')).filter((f) => f.endsWith('.gd'));
  assert.ok(files.length > 0);
  for (const f of files) assert.ok(readFileSync(join(REPO, 'godot', 'art', f), 'utf8').startsWith(GD_HEADER[0]), f);
});

// --- made-up trees -------------------------------------------------------------------------------------

function makeTree(files) {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-license-'));
  const all = { 'LICENSE-ASSETS': 'The art: godot/art/\n', ...files };
  for (const [name, content] of Object.entries(all)) {
    const path = join(root, name);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, content);
  }
  return root;
}

function problemsOf(files) {
  const root = makeTree(files);
  try {
    return checkLicense(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const GD = `${GD_HEADER.join('\n')}\nextends RefCounted\n`;
const JS = `${JS_HEADER.join('\n')}\nexport {};\n`;
const hash = (text) => createHash('sha256').update(text).digest('hex');

test('a good tree has no problems', () => {
  assert.deepEqual(problemsOf({ 'godot/art/a.gd': GD, 'godot/art/b.js': JS, 'godot/src/x.gd': 'extends Node\n' }), []);
});

test('a .gd or .js file in art/ without the header fails', () => {
  const found = problemsOf({ 'godot/art/a.gd': 'extends Node\n', 'godot/art/b.js': '// hello\n' });
  assert.equal(found.filter((p) => p.includes('missing the copyright header')).length, 2);
});

test('LICENSE-ASSETS must name godot/art/', () => {
  assert.ok(problemsOf({ 'LICENSE-ASSETS': 'nothing here\n', 'godot/art/a.gd': GD }).some((p) => p.includes('LICENSE-ASSETS')));
});

test('drawing and sound calls outside art/ fail, but comments and addons do not', () => {
  const bad = problemsOf({
    'godot/art/a.gd': GD,
    'godot/src/view.gd': 'func _draw() -> void:\n\tdraw_rect(Rect2(), Color.RED)\n',
    'godot/src/snd.gd': 'var s := AudioStreamWAV.new()\n',
    'godot/src/tex.gd': 'var t := ImageTexture.new()\n\tdraw_texture_rect(t, Rect2(), false)\n',
  });
  assert.equal(bad.filter((p) => p.startsWith('src/view.gd')).length >= 2, true);
  assert.ok(bad.some((p) => p.startsWith('src/snd.gd')));
  assert.ok(bad.some((p) => p.startsWith('src/tex.gd')));
  const fine = problemsOf({
    'godot/art/a.gd': GD,
    'godot/src/note.gd': '# The art code calls draw_rect and _draw.\nextends Node\n',
    'godot/addons/lib/x.gd': 'func _draw() -> void:\n\tdraw_rect(Rect2(), Color.RED)\n',
  });
  assert.deepEqual(fine, []);
});

test('the art code itself may draw', () => {
  assert.deepEqual(problemsOf({ 'godot/art/a.gd': `${GD}func _draw() -> void:\n\tdraw_rect(Rect2(), Color.RED)\n` }), []);
});

test('a shader file fails', () => {
  assert.ok(problemsOf({ 'godot/art/a.gd': GD, 'godot/art/x.gdshader': 'shader_type canvas_item;\n' }).some((p) => p.includes('shader')));
});

test('an image or a sound file outside art/ fails, inside art/ they need the manifest', () => {
  assert.ok(problemsOf({ 'godot/art/a.gd': GD, 'godot/src/logo.png': 'x' }).some((p) => p.startsWith('src/logo.png')));
  assert.ok(problemsOf({ 'godot/art/a.gd': GD, 'godot/other/tune.ogg': 'x' }).some((p) => p.startsWith('other/tune.ogg')));
  assert.ok(problemsOf({ 'godot/art/a.gd': GD, 'godot/art/images/p.png': 'x' }).some((p) => p.includes('MANIFEST.txt is missing')));
});

test('art/images/ and art/sound/ take only their own kind of file', () => {
  assert.ok(problemsOf({ 'godot/art/a.gd': GD, 'godot/art/images/code.gd': GD }).some((p) => p.includes('may hold only')));
  assert.ok(problemsOf({ 'godot/art/a.gd': GD, 'godot/art/sound/p.png': 'x' }).some((p) => p.includes('may hold only')));
});

test('the manifest must list each file with the right SHA-256 hash', () => {
  const good = `${MANIFEST_FIRST_LINE}\n${hash('img')}  images/p.png\n${hash('snd')}  sound/t.ogg\n`;
  const files = { 'godot/art/a.gd': GD, 'godot/art/images/p.png': 'img', 'godot/art/sound/t.ogg': 'snd' };
  assert.deepEqual(problemsOf({ ...files, 'godot/art/MANIFEST.txt': good }), []);
  const edited = { ...files, 'godot/art/images/p.png': 'changed by hand' };
  assert.ok(problemsOf({ ...edited, 'godot/art/MANIFEST.txt': good }).some((p) => p.includes('does not match')));
  assert.ok(problemsOf({ ...files, 'godot/art/MANIFEST.txt': `${MANIFEST_FIRST_LINE}\n${hash('img')}  images/p.png\n` }).some((p) => p.includes('sound/t.ogg is not listed')));
  assert.ok(problemsOf({ ...files, 'godot/art/MANIFEST.txt': `${good}${hash('x')}  images/gone.png\n` }).some((p) => p.includes('does not exist')));
  assert.ok(problemsOf({ ...files, 'godot/art/MANIFEST.txt': good.replace(MANIFEST_FIRST_LINE, 'hello') }).some((p) => p.includes('first line')));
});
