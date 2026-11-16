// The checks of the license split between the MIT code and the art (see LICENSE-ASSETS).
// tools/license.test.mjs runs them on the real tree and on small made-up trees.
//
// The check is a heuristic. It finds the usual ways to draw or to make sound, not every way.
// A person reviews each change near the line.

import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

export const GD_HEADER = [
  '# Copyright (c) 2026 Pawel Gorazda. All rights reserved.',
  '# Part of the Agent Workshop art: see LICENSE-ASSETS in the repository root. The MIT license does not cover this file.',
];
export const JS_HEADER = GD_HEADER.map((line) => `//${line.slice(1)}`);
export const MANIFEST_FIRST_LINE = 'Copyright (c) 2026 Pawel Gorazda. All rights reserved.';

// Calls that draw or make sound. Outside godot/art/ they are a sign of a mistake.
export const DRAWING_PATTERNS = [
  'set_pixel',
  'fill_rect',
  'blend_rect',
  'Image\\.create',
  'ImageTexture',
  '_draw\\b',
  'draw_rect',
  'draw_string',
  'draw_texture\\w*',
  'AudioStreamGenerator',
  'AudioStreamWAV',
];

const IMAGE_EXT = ['.png', '.jpg', '.jpeg', '.webp', '.svg', '.gif', '.bmp', '.ico', '.icns', '.tga', '.exr', '.hdr'];
const SOUND_EXT = ['.wav', '.ogg', '.mp3', '.flac', '.opus'];
// Folders that hold no source of ours: the addons, and the folders that Godot and the scripts make (out/ holds the clips and frames of tools/record.mjs).
const SKIPPED = new Set(['addons', '.godot', '.editor', 'node_modules', 'test-results', 'out']);

const posix = (path) => path.split(sep).join('/');
const readText = (path) => readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const sha256 = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');

/** All files under `dir`, as absolute paths. `skip` is a set of folder names to leave out. */
function walk(dir, skip = new Set()) {
  const found = [];
  if (!existsSync(dir)) return found;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!skip.has(entry.name)) found.push(...walk(path, skip));
    } else found.push(path);
  }
  return found;
}

const extOf = (file) => {
  const dot = file.lastIndexOf('.');
  return dot < 0 ? '' : file.slice(dot).toLowerCase();
};

/** The text of a GDScript file without its comments. A `#` inside a string also cuts the line: it is a heuristic. */
export function stripGdComments(text) {
  return text
    .split('\n')
    .map((line) => line.replace(/#.*$/, ''))
    .join('\n');
}

/**
 * Checks a repository tree. `root` is the repository root (it holds `godot/` and `LICENSE-ASSETS`).
 * Returns a list of problem strings. An empty list means that all checks pass.
 */
export function checkLicense(root) {
  const problems = [];
  const godot = join(root, 'godot');
  const art = join(godot, 'art');
  const artRel = (file) => posix(relative(godot, file));

  // 1. Headers in godot/art/.
  const artFiles = walk(art);
  for (const file of artFiles) {
    const ext = extOf(file);
    const lines = ext === '.gd' ? GD_HEADER : ext === '.js' ? JS_HEADER : null;
    if (!lines) continue;
    if (!readText(file).startsWith(`${lines.join('\n')}\n`)) problems.push(`${artRel(file)}: missing the copyright header`);
  }

  // 2. images/ and sound/ hold only image and sound files, and the manifest matches them.
  const rendered = [];
  for (const [folder, allowed] of [
    ['images', IMAGE_EXT],
    ['sound', SOUND_EXT],
  ]) {
    for (const file of walk(join(art, folder))) {
      const ext = extOf(file);
      if (ext === '.import' || ext === '.uid') continue;
      if (!allowed.includes(ext)) problems.push(`${artRel(file)}: art/${folder}/ may hold only ${allowed.join(' ')} files`);
      else rendered.push(file);
    }
  }
  const manifestPath = join(art, 'MANIFEST.txt');
  if (existsSync(manifestPath)) {
    const lines = readText(manifestPath).split('\n');
    if (lines[0] !== MANIFEST_FIRST_LINE) problems.push('art/MANIFEST.txt: the first line must be the copyright line');
    const listed = new Map();
    for (const line of lines.slice(1)) {
      const match = /^([0-9a-f]{64}) {2}(\S.*)$/.exec(line);
      if (match) listed.set(match[2], match[1]);
      else if (line.trim() && !line.startsWith('#')) problems.push(`art/MANIFEST.txt: cannot read the line "${line}"`);
    }
    const wanted = new Set(rendered.map((file) => posix(relative(art, file))));
    for (const name of wanted) {
      if (!listed.has(name)) problems.push(`art/MANIFEST.txt: ${name} is not listed`);
      else if (listed.get(name) !== sha256(join(art, name))) problems.push(`art/MANIFEST.txt: the hash of ${name} does not match the file`);
    }
    for (const name of listed.keys()) if (!wanted.has(name)) problems.push(`art/MANIFEST.txt: ${name} is listed, but the file does not exist`);
  } else if (rendered.length > 0) {
    problems.push('art/MANIFEST.txt is missing: the files in art/images/ and art/sound/ need hashes');
  }

  // 3. LICENSE-ASSETS names godot/art/.
  const licensePath = join(root, 'LICENSE-ASSETS');
  if (!existsSync(licensePath) || !readText(licensePath).includes('godot/art/')) problems.push('LICENSE-ASSETS does not name godot/art/');

  // 4. No drawing or sound code outside godot/art/ and godot/addons/.
  const patterns = DRAWING_PATTERNS.map((pattern) => ({ pattern, regex: new RegExp(`\\b${pattern}`) }));
  const outsideArt = walk(godot, SKIPPED).filter((file) => !posix(relative(godot, file)).startsWith('art/'));
  for (const file of outsideArt) {
    if (extOf(file) !== '.gd') continue;
    const code = stripGdComments(readText(file));
    for (const { pattern, regex } of patterns) {
      if (regex.test(code)) problems.push(`${artRel(file)}: matches the drawing or sound pattern "${pattern}", which belongs in godot/art/`);
    }
  }

  // 5. No shader file, and no image or sound file outside godot/art/ and godot/addons/.
  for (const file of walk(godot, SKIPPED)) {
    const ext = extOf(file);
    if (ext === '.gdshader' || ext === '.gdshaderinc') problems.push(`${artRel(file)}: shader files are not allowed`);
    if (posix(relative(godot, file)).startsWith('art/')) continue;
    if ((IMAGE_EXT.includes(ext) || SOUND_EXT.includes(ext)) && !statSync(file).isDirectory()) {
      problems.push(`${artRel(file)}: image and sound files belong in godot/art/`);
    }
  }
  return problems;
}
