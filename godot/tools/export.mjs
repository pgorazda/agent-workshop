#!/usr/bin/env node
// Exports the Godot client as an app for Windows, Linux or macOS. The apps are NOT signed or notarized.
//
//   cd godot
//   node tools/export.mjs --templates-only            # only get the export templates (about 1.3 GB download)
//   node tools/export.mjs --platform windows          # out/export/windows/AgentWorkshop.exe
//   node tools/export.mjs --platform linux            # out/export/linux/AgentWorkshop.x86_64
//   node tools/export.mjs --platform macos            # out/export/macos/AgentWorkshop.zip (an .app inside, universal)
//   node tools/export.mjs --platform windows-arm64    # out/export/windows-arm64/AgentWorkshop.exe
//   node tools/export.mjs --platform linux-arm64      # out/export/linux-arm64/AgentWorkshop.arm64
//   node tools/export.mjs --platform all              # all five
//   options: --out <folder>  (default: out/export)   --debug  (a debug export instead of a release export)
//
// Export templates: the tool downloads the official archive `Godot_v<version>_export_templates.tpz` from godotengine.org, checks its
// SHA-512 hash against the official SHA512-SUMS.txt of the release (the table below), and installs the templates that the chosen
// platforms need into the folder where the editor looks for them (`<user data>/Godot/export_templates/<version>.stable/`). The
// archive stays in godot/.editor/ (git-ignored) until the install works, then the tool deletes it, because it is large.
// If the templates are installed already, the tool downloads nothing.
//
// What is NOT done here: signing, notarization and any identity. The presets (export_presets.cfg) hold no secrets. The apps are
// unsigned. See godot/README.md for what a user sees (Windows SmartScreen, macOS Gatekeeper).
//
// The editor is found as in the other tools (GODOT, or the copy of get-godot.mjs).

import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { EDITOR_DIR, GODOT_DIR, pinnedVersion, resolveGodot } from './godot-path.mjs';

/** The official template archives. Key: the version. The hash is in SHA512-SUMS.txt of the release in godotengine/godot-builds. */
export const TEMPLATE_ARCHIVES = {
  '4.7.2': {
    file: 'Godot_v4.7.2-stable_export_templates.tpz',
    sha512: 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079',
  },
};

/**
 * The export presets: the name in export_presets.cfg, the file name and the templates that the export needs.
 * `os` and `arch` name the app in a release file (see package.mjs). The macOS app is universal: it runs on Intel and on Apple silicon.
 * The template names were checked in the file list of the official archive of 4.7.2.
 */
export const PLATFORMS = {
  windows: {
    preset: 'Windows Desktop',
    file: 'AgentWorkshop.exe',
    os: 'windows',
    arch: 'x86_64',
    templates: ['windows_release_x86_64.exe', 'windows_debug_x86_64.exe', 'windows_release_x86_64_console.exe', 'windows_debug_x86_64_console.exe'],
  },
  'windows-arm64': {
    preset: 'Windows Desktop ARM64',
    file: 'AgentWorkshop.exe',
    os: 'windows',
    arch: 'arm64',
    templates: ['windows_release_arm64.exe', 'windows_debug_arm64.exe', 'windows_release_arm64_console.exe', 'windows_debug_arm64_console.exe'],
  },
  linux: {
    preset: 'Linux',
    file: 'AgentWorkshop.x86_64',
    os: 'linux',
    arch: 'x86_64',
    templates: ['linux_release.x86_64', 'linux_debug.x86_64'],
  },
  'linux-arm64': {
    preset: 'Linux ARM64',
    file: 'AgentWorkshop.arm64',
    os: 'linux',
    arch: 'arm64',
    templates: ['linux_release.arm64', 'linux_debug.arm64'],
  },
  macos: {
    preset: 'macOS',
    file: 'AgentWorkshop.zip',
    os: 'macos',
    arch: 'universal',
    templates: ['macos.zip'],
  },
};

/** Files that every platform needs. */
export const COMMON_TEMPLATES = ['version.txt', 'icudt_godot.dat'];

export function archiveFor(version) {
  const entry = TEMPLATE_ARCHIVES[version];
  if (!entry) throw new Error(`No pinned hash for the export templates of Godot ${version}. Add it to TEMPLATE_ARCHIVES in tools/export.mjs.`);
  return entry;
}

/** The official download page of godotengine.org. It redirects to the release file. */
export function templatesUrl(version) {
  return `https://downloads.godotengine.org/?version=${version}&flavor=stable&slug=export_templates.tpz&platform=templates`;
}

/** The folder in which the editor looks for the export templates of a version. */
export function templatesDir(version = pinnedVersion(), { platform = process.platform, env = process.env, home = homedir() } = {}) {
  if (env.GODOT_TEMPLATES_DIR) return join(env.GODOT_TEMPLATES_DIR, `${version}.stable`);
  let base;
  if (platform === 'win32') base = join(env.APPDATA ?? join(home, 'AppData', 'Roaming'), 'Godot');
  else if (platform === 'darwin') base = join(home, 'Library', 'Application Support', 'Godot');
  else base = join(env.XDG_DATA_HOME ?? join(home, '.local', 'share'), 'godot');
  return join(base, 'export_templates', `${version}.stable`);
}

export function platformsFor(name) {
  if (name === 'all') return Object.keys(PLATFORMS);
  if (!PLATFORMS[name]) throw new Error(`Unknown platform "${name}". Use ${Object.keys(PLATFORMS).join(', ')} or all.`);
  return [name];
}

/** The template files that the given platforms need, with the common ones. */
export function neededTemplates(names) {
  return [...COMMON_TEMPLATES, ...names.flatMap((name) => PLATFORMS[name].templates)];
}

/** The files of `needed` that are not in `folder` (or are empty). */
export function missingTemplates(folder, needed) {
  return needed.filter((name) => {
    const path = join(folder, name);
    return !existsSync(path) || statSync(path).size === 0;
  });
}

/** True when the installed version.txt is the pinned version ("4.7.2.stable"). */
export function versionTextMatches(folder, version) {
  const path = join(folder, 'version.txt');
  return existsSync(path) && readFileSync(path, 'utf8').trim() === `${version}.stable`;
}

export async function sha512OfFile(path) {
  const hash = createHash('sha512');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

/** Throws unless the file has the pinned hash. Deletes a wrong file. */
export async function verifyArchive(path, expected) {
  const actual = await sha512OfFile(path);
  if (actual !== expected) {
    rmSync(path, { force: true });
    throw new Error(`Hash mismatch for ${path}.\n  expected ${expected}\n  actual   ${actual}\nThe file was deleted.`);
  }
}

/** The path of an unpacked file must stay in the folder. Gives the checked path. */
export function safeJoin(folder, name) {
  if (name.includes('..') || name.startsWith('/') || /^[A-Za-z]:/.test(name)) throw new Error(`Unsafe file name: ${name}`);
  return join(folder, name);
}

function unpack(archive, folder, members) {
  // bsdtar (Windows 10 and later, macOS) reads zip files. Linux often has unzip only.
  const names = members.map((m) => `templates/${m}`);
  // On Windows use the system tar (bsdtar): a tar of Git for Windows cannot read zip files.
  const tarProgram = process.platform === 'win32' ? join(process.env.SystemRoot ?? 'C:\Windows', 'System32', 'tar.exe') : 'tar';
  const tar = spawnSync(tarProgram, ['-xf', archive, '-C', folder, ...names], { stdio: 'inherit' });
  if (tar.status === 0) return;
  const unzip = spawnSync('unzip', ['-o', archive, ...names, '-d', folder], { stdio: 'inherit' });
  if (unzip.status !== 0) throw new Error('Could not unpack the archive: neither "tar" nor "unzip" worked.');
}

/** Makes sure that the templates for `names` are installed. Returns the folder. */
export async function getTemplates(names, { env = process.env, log = console.log } = {}) {
  const version = pinnedVersion();
  const target = templatesDir(version, { env });
  const needed = neededTemplates(names);
  if (versionTextMatches(target, version) && missingTemplates(target, needed).length === 0) {
    log(`Export templates ${version} are installed.`);
    return target;
  }
  const entry = archiveFor(version);
  const folder = join(EDITOR_DIR, version);
  mkdirSync(folder, { recursive: true });
  const archive = join(folder, entry.file);
  let good = false;
  if (existsSync(archive)) {
    log('Checking the archive that is already here ...');
    good = (await sha512OfFile(archive)) === entry.sha512;
  }
  if (!good) {
    const url = templatesUrl(version);
    log(`Downloading ${entry.file} from godotengine.org (about 1.3 GB) ...`);
    const response = await fetch(url, { redirect: 'follow' });
    if (!response.ok || !response.body) throw new Error(`Download failed: HTTP ${response.status} for ${url}`);
    await pipeline(Readable.fromWeb(response.body), createWriteStream(archive));
    await verifyArchive(archive, entry.sha512);
  }
  log('Hash is correct. Installing the templates for ' + names.join(', ') + ' ...');
  const scratch = join(folder, 'unpacked');
  rmSync(scratch, { recursive: true, force: true });
  mkdirSync(scratch, { recursive: true });
  unpack(archive, scratch, needed);
  mkdirSync(target, { recursive: true });
  for (const name of needed) {
    const from = safeJoin(join(scratch, 'templates'), name);
    if (!existsSync(from)) throw new Error(`The archive did not contain ${name}.`);
    // copy by stream: the files are large
    await pipeline(createReadStream(from), createWriteStream(safeJoin(target, name)));
  }
  rmSync(scratch, { recursive: true, force: true });
  rmSync(archive, { force: true });
  if (!versionTextMatches(target, version)) throw new Error(`version.txt in ${target} is not ${version}.stable.`);
  log(`Installed in ${target}`);
  return target;
}

function run(godot, args, label) {
  const result = spawnSync(godot, args, { cwd: GODOT_DIR, encoding: 'utf8' });
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  if (result.status !== 0) throw new Error(`${label} failed (exit code ${result.status}):\n${output}`);
  return output;
}

/** Exports one platform. Returns { path, bytes, output }. */
export function exportPlatform(name, { godot = resolveGodot(), outDir = join(GODOT_DIR, 'out', 'export'), debug = false, log = console.log } = {}) {
  const spec = PLATFORMS[name];
  const folder = join(outDir, name);
  rmSync(folder, { recursive: true, force: true });
  mkdirSync(folder, { recursive: true });
  const path = join(folder, spec.file);
  log(`Exporting "${spec.preset}" to ${path} ...`);
  const output = run(godot, ['--headless', '--path', GODOT_DIR, debug ? '--export-debug' : '--export-release', spec.preset, path], `The export of ${name}`);
  if (/^(ERROR|SCRIPT ERROR)/m.test(output)) throw new Error(`The export of ${name} printed errors:\n${output}`);
  if (!existsSync(path)) throw new Error(`The export of ${name} wrote no file:\n${output}`);
  return { path, bytes: statSync(path).size, output, files: readdirSync(folder) };
}

export function parseArgs(argv) {
  const options = { platform: null, outDir: null, debug: false, templatesOnly: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--platform') options.platform = argv[++i];
    else if (arg.startsWith('--platform=')) options.platform = arg.slice(11);
    else if (arg === '--out') options.outDir = argv[++i];
    else if (arg === '--debug') options.debug = true;
    else if (arg === '--templates-only') options.templatesOnly = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (!options.platform && !options.templatesOnly) throw new Error('Give --platform windows|windows-arm64|linux|linux-arm64|macos|all, or --templates-only.');
  return options;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const names = platformsFor(options.platform ?? 'all');
  await getTemplates(names);
  if (options.templatesOnly) return;
  const godot = resolveGodot();
  run(godot, ['--headless', '--path', GODOT_DIR, '--import'], 'The import');
  for (const name of names) {
    const result = exportPlatform(name, { godot, debug: options.debug, ...(options.outDir ? { outDir: options.outDir } : {}) });
    console.log(`${name}: ${result.path} (${(result.bytes / 1048576).toFixed(1)} MB; files: ${result.files.join(', ')})`);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(`error: ${err.message}`);
    process.exitCode = 1;
  });
}
