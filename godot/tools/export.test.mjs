// Tests the export presets and the parts of export.mjs that need no network and no export (phase G-9):  node --test
// A full export is not run here: it needs the templates (1.3 GB) and takes a minute. Run it with tools/export.mjs.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { GODOT_DIR, pinnedVersion } from './godot-path.mjs';
import {
  COMMON_TEMPLATES, PLATFORMS, TEMPLATE_ARCHIVES, archiveFor, missingTemplates, neededTemplates, parseArgs, platformsFor, safeJoin,
  sha512OfFile, templatesDir, templatesUrl, verifyArchive, versionTextMatches,
} from './export.mjs';

/** Reads export_presets.cfg: [{ section, values }] with the values as text (quotes removed). */
function readPresets(text = readFileSync(join(GODOT_DIR, 'export_presets.cfg'), 'utf8')) {
  const sections = [];
  let current = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith(';')) continue;
    const header = /^\[(.+)\]$/.exec(line);
    if (header) {
      current = { section: header[1], values: {} };
      sections.push(current);
      continue;
    }
    const eq = line.indexOf('=');
    if (eq < 0 || !current) throw new Error(`cannot read the line: ${line}`);
    let value = line.slice(eq + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1);
    current.values[line.slice(0, eq).trim()] = value;
  }
  return sections;
}

const presets = () => {
  const sections = readPresets();
  return sections.filter((s) => /^preset\.\d+$/.test(s.section)).map((s) => ({
    ...s.values,
    options: sections.find((o) => o.section === `${s.section}.options`)?.values ?? {},
  }));
};

/** A filter of the preset ("a/*, *.md") as a test for a path that is relative to the project. */
function filterMatcher(filter) {
  const parts = filter.split(',').map((p) => p.trim()).filter(Boolean);
  const regexes = parts.map((p) => new RegExp(`^${p.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`));
  return (path) => regexes.some((re) => re.test(path));
}

function files(folder, base = folder) {
  const out = [];
  for (const entry of readdirSync(folder, { withFileTypes: true })) {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) out.push(...files(path, base));
    else out.push(relative(base, path).split('\\').join('/'));
  }
  return out;
}

test('there is one preset for each desktop platform, named as the tool expects', () => {
  const list = presets();
  assert.deepEqual(list.map((p) => p.name).sort(), Object.values(PLATFORMS).map((p) => p.preset).sort());
  assert.deepEqual(list.map((p) => p.platform).sort(), ['Linux', 'Windows Desktop', 'macOS']);
});

test('the presets hold no secret and no identity', () => {
  const text = readFileSync(join(GODOT_DIR, 'export_presets.cfg'), 'utf8');
  for (const preset of presets()) {
    for (const [key, value] of Object.entries(preset.options)) {
      if (/password|secret|token|identity|certificate|keystore|apple_team|api_key|provisioning|entitlements/i.test(key)) {
        assert.ok(value === '' || value === 'false' || value === '0', `${preset.name}: ${key} must be empty`);
      }
    }
    assert.equal(preset.encrypt_pck, 'false', `${preset.name}: no encryption key is stored`);
    assert.equal(preset.export_path, '', `${preset.name}: the tool gives the output path`);
  }
  assert.ok(!/BEGIN [A-Z ]*PRIVATE KEY|ghp_|AKIA[0-9A-Z]{12}/.test(text));
  const windows = presets().find((p) => p.platform === 'Windows Desktop');
  assert.equal(windows.options['codesign/enable'], 'false', 'Windows: not signed');
  const mac = presets().find((p) => p.platform === 'macOS');
  assert.equal(mac.options['notarization/notarization'], '0', 'macOS: not notarized');
  assert.equal(mac.options['codesign/codesign'], '1', 'macOS: the built-in ad-hoc signature only (it has no identity)');
});

test('the presets hold no absolute path and no path of a user', () => {
  const text = readFileSync(join(GODOT_DIR, 'export_presets.cfg'), 'utf8');
  assert.ok(!/(^|[^A-Za-z])[A-Za-z]:[\\/]/.test(text), 'no drive letter');
  assert.ok(!/(^|[\s="])\/(Users|home|usr|opt|var|tmp|mnt|c)\//.test(text), 'no Unix path');
  assert.ok(!/~\//.test(text) && !/\\\\/.test(text));
  for (const preset of presets()) {
    for (const [key, value] of Object.entries(preset.options)) {
      if (value.startsWith('res://')) assert.ok(existsSync(join(GODOT_DIR, value.slice('res://'.length))), `${preset.name}: ${key} exists`);
    }
  }
});

test('every preset leaves out the tests, the tools, the spike, GUT, the output and the texts, and adds the scene files', () => {
  for (const preset of presets()) {
    const excluded = filterMatcher(preset.exclude_filter);
    for (const path of ['test/test_clock.gd', 'tools/export.mjs', 'spikes/s6/s6_runner.gd', 'addons/gut/gut.gd', 'out/export/a.exe', 'README.md', 'art/image_src/look.js', 'art/sound_src/sound.js']) {
      assert.ok(excluded(path), `${preset.name}: ${path} is excluded`);
    }
    assert.equal(preset.include_filter, 'demo/*.json', `${preset.name}: the scene files are included`);
    assert.equal(preset.export_filter, 'all_resources', `${preset.name}: the client loads sounds by a name that it builds`);
  }
});

test('nothing that the client needs at run time is excluded', () => {
  const needed = [];
  for (const folder of ['demo', 'art/images', 'art/sound', 'src']) {
    for (const path of files(join(GODOT_DIR, folder))) {
      if (path.endsWith('.import') || path.endsWith('.uid') || path.endsWith('.md')) continue;
      needed.push(`${folder}/${path}`);
    }
  }
  for (const path of ['project.godot', 'art/atlas_data.gd', 'art/atlas.gd', 'art/draw_kit.gd']) needed.push(path);
  assert.ok(needed.length > 40);
  for (const preset of presets()) {
    const excluded = filterMatcher(preset.exclude_filter);
    for (const path of needed) assert.ok(!excluded(path), `${preset.name}: ${path} must not be excluded`);
  }
  // every res:// path that a script or a scene of src/ names must stay out of the excluded folders
  const excludedFolders = /^res:\/\/(test|tools|spikes|addons|out)\//;
  for (const path of files(join(GODOT_DIR, 'src'))) {
    if (!/\.(gd|tscn)$/.test(path)) continue;
    const code = readFileSync(join(GODOT_DIR, 'src', path), 'utf8');
    for (const [, ref] of code.matchAll(/"(res:\/\/[^"]+)"/g)) assert.ok(!excludedFolders.test(ref), `src/${path} names ${ref}`);
  }
});

test('the product name, the version and the icon are set, and the versions agree', () => {
  const project = readFileSync(join(GODOT_DIR, 'project.godot'), 'utf8');
  const version = /^config\/version="([^"]+)"/m.exec(project)?.[1];
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.match(project, /^config\/icon="res:\/\/art\/images\/app_icon\.png"/m);
  const windows = presets().find((p) => p.platform === 'Windows Desktop').options;
  const mac = presets().find((p) => p.platform === 'macOS').options;
  assert.equal(windows['application/product_name'], 'Agent Workshop');
  assert.equal(windows['application/file_version'], `${version}.0`);
  assert.equal(windows['application/product_version'], `${version}.0`);
  assert.equal(windows['application/modify_resources'], 'true');
  assert.equal(windows['application/icon'], 'res://art/images/app_icon.png');
  assert.equal(mac['application/icon'], 'res://art/images/app_icon.png');
  assert.equal(mac['application/short_version'], version);
  assert.equal(mac['application/version'], version);
  assert.match(mac['application/bundle_identifier'], /^[A-Za-z0-9.-]+$/);
  // macOS universal and arm64 need the ETC2 ASTC import in the project (the export says so)
  assert.match(project, /^textures\/vram_compression\/import_etc2_astc=true/m);
});

test('the app icon is a square PNG of 512 pixels', () => {
  const bytes = readFileSync(join(GODOT_DIR, 'art', 'images', 'app_icon.png'));
  assert.equal(bytes.subarray(1, 4).toString('latin1'), 'PNG');
  assert.equal(bytes.readUInt32BE(16), 512);
  assert.equal(bytes.readUInt32BE(20), 512);
});

test('the template archive of the pinned version has a SHA-512 hash and an address on godotengine.org', () => {
  const version = pinnedVersion();
  const entry = archiveFor(version);
  assert.match(entry.sha512, /^[0-9a-f]{128}$/);
  assert.equal(entry.file, `Godot_v${version}-stable_export_templates.tpz`);
  const url = new URL(templatesUrl(version));
  assert.equal(url.hostname, 'downloads.godotengine.org');
  assert.equal(url.searchParams.get('slug'), 'export_templates.tpz');
  assert.equal(url.searchParams.get('version'), version);
  assert.throws(() => archiveFor('9.9.9'), /No pinned hash/);
  assert.ok(TEMPLATE_ARCHIVES[version]);
});

test('the templates go where the editor looks for them', () => {
  assert.equal(templatesDir('4.7.2', { platform: 'win32', env: { APPDATA: 'A:\\data' }, home: 'H' }), join('A:\\data', 'Godot', 'export_templates', '4.7.2.stable'));
  assert.equal(templatesDir('4.7.2', { platform: 'linux', env: { XDG_DATA_HOME: '/x' }, home: '/h' }), join('/x', 'godot', 'export_templates', '4.7.2.stable'));
  assert.equal(templatesDir('4.7.2', { platform: 'linux', env: {}, home: '/h' }), join('/h', '.local', 'share', 'godot', 'export_templates', '4.7.2.stable'));
  assert.equal(templatesDir('4.7.2', { platform: 'darwin', env: {}, home: '/h' }), join('/h', 'Library', 'Application Support', 'Godot', 'export_templates', '4.7.2.stable'));
  assert.equal(templatesDir('4.7.2', { platform: 'win32', env: { GODOT_TEMPLATES_DIR: '/t' } }), join('/t', '4.7.2.stable'));
});

test('the needed templates, and the check for missing ones', () => {
  assert.deepEqual(platformsFor('all'), ['windows', 'linux', 'macos']);
  assert.throws(() => platformsFor('amiga'), /Unknown platform/);
  const needed = neededTemplates(['macos', 'linux']);
  for (const name of [...COMMON_TEMPLATES, 'macos.zip', 'linux_release.x86_64']) assert.ok(needed.includes(name), name);
  assert.ok(!needed.some((n) => n.startsWith('windows_')));
  const dir = mkdtempSync(join(tmpdir(), 'agent-workshop-templates-'));
  try {
    writeFileSync(join(dir, 'version.txt'), '4.7.2.stable\n');
    writeFileSync(join(dir, 'macos.zip'), 'x');
    writeFileSync(join(dir, 'empty.bin'), '');
    assert.ok(versionTextMatches(dir, '4.7.2'));
    assert.ok(!versionTextMatches(dir, '4.7.3'));
    assert.deepEqual(missingTemplates(dir, ['version.txt', 'macos.zip', 'empty.bin', 'gone.bin']), ['empty.bin', 'gone.bin']);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a downloaded archive with a wrong hash is deleted and refused, and one with the right hash is accepted', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'agent-workshop-archive-'));
  try {
    const path = join(dir, 'a.tpz');
    writeFileSync(path, 'abc');
    const abc = 'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f';
    assert.equal(await sha512OfFile(path), abc);
    await verifyArchive(path, abc);
    assert.ok(existsSync(path));
    await assert.rejects(() => verifyArchive(path, '0'.repeat(128)), /Hash mismatch/);
    assert.ok(!existsSync(path), 'the file is deleted');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an unpacked file name may not leave the folder', () => {
  assert.equal(safeJoin('/a', 'b.exe'), join('/a', 'b.exe'));
  for (const bad of ['../x', 'a/../../x', '/etc/passwd', 'C:\\x', 'C:/x']) assert.throws(() => safeJoin('/a', bad), /Unsafe/, bad);
});

test('the command line', () => {
  assert.deepEqual(parseArgs(['--platform', 'linux']), { platform: 'linux', outDir: null, debug: false, templatesOnly: false });
  assert.equal(parseArgs(['--platform=all', '--debug']).debug, true);
  assert.equal(parseArgs(['--templates-only']).templatesOnly, true);
  assert.throws(() => parseArgs([]), /--platform/);
  assert.throws(() => parseArgs(['--platform', 'linux', '--sign']), /Unknown option/);
});

test('the export folder and the template archive are not in git', () => {
  const ignore = readFileSync(join(GODOT_DIR, '..', '.gitignore'), 'utf8');
  assert.match(ignore, /^godot\/out\/$/m);
  assert.match(ignore, /^godot\/\.editor\/$/m);
  assert.ok(statSync(join(GODOT_DIR, 'export_presets.cfg')).size > 0);
});
