#!/usr/bin/env node
// Makes the release files from the exports of export.mjs.
//
//   cd godot
//   node tools/export.mjs --platform all
//   node tools/package.mjs --version 0.2.0            # out/release/AgentWorkshop-0.2.0-<os>-<arch>.zip|tar.gz and SHA256SUMS
//   node tools/package.mjs --version 0.2.0 --bridge-in out/bridge      also the bridge archives (see below)
//   options: --in <folder>  (default: out/export)   --out <folder>  (default: out/release)   --platform <name|all>
//            --bridge-in <folder>  the bridge binaries: <folder>/<platform>/agent-workshop-bridge (.exe for Windows)
//
// One archive for each platform of export.mjs. The names are `AgentWorkshop-<version>-<os>-<arch>` with `.zip` (Windows and macOS)
// or `.tar.gz` (Linux). Inside is one folder of the same name with the app, `LICENSE`, `LICENSE-ASSETS` and `THIRD-PARTY-NOTICES.txt`. The macOS app is
// universal, so its file name says `macos-universal`. The Linux file gets the executable flag. The file SHA256SUMS lists the
// SHA-256 hash of every archive in the format of `sha256sum -c`.
//
// With --bridge-in there is one more archive for each platform: `AgentWorkshopBridge-<version>-<os>-<arch>`, with the bridge
// binary and `LICENSE` (the bridge is code, so no `LICENSE-ASSETS`). The bridge has its own archives, not the app's, so a person
// downloads the bridge only if they want live events. The Linux and the macOS binary keep the executable flag.
//
// The tool needs `zip` and `unzip` (macOS archives are opened and made again) and `tar`. It runs them without a shell.

import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { GODOT_DIR } from './godot-path.mjs';
import { PLATFORMS, platformsFor } from './export.mjs';
import { SEMVER } from './version.mjs';

export const REPO_ROOT = join(GODOT_DIR, '..');
export const LICENSE_FILES = ['LICENSE', 'LICENSE-ASSETS'];
/** The bridge is code only. */
export const BRIDGE_LICENSE_FILES = ['LICENSE'];
/** The notices of the parts that each program carries (the Godot engine, the Rust crates). They go next to the licenses. */
export const NOTICE_FILES = 'THIRD-PARTY-NOTICES.txt';
export const APP_NOTICES_PATH = 'godot/THIRD-PARTY-NOTICES.txt';
export const BRIDGE_NOTICES_PATH = 'bridge/THIRD-PARTY-NOTICES.txt';

/** `AgentWorkshop-0.2.0-linux-arm64` */
export function baseName(version, platform) {
  const spec = PLATFORMS[platform];
  if (!spec) throw new Error(`Unknown platform "${platform}".`);
  if (!SEMVER.test(version)) throw new Error(`"${version}" is not a version like 1.2.3.`);
  return `AgentWorkshop-${version}-${spec.os}-${spec.arch}`;
}

/** The archive file name: `.tar.gz` for Linux, `.zip` for the others. */
export function archiveName(version, platform) {
  return `${baseName(version, platform)}${PLATFORMS[platform].os === 'linux' ? '.tar.gz' : '.zip'}`;
}

/** The file name of the bridge binary for a platform. */
export function bridgeFileName(platform) {
  const spec = PLATFORMS[platform];
  if (!spec) throw new Error(`Unknown platform "${platform}".`);
  return spec.os === 'windows' ? 'agent-workshop-bridge.exe' : 'agent-workshop-bridge';
}

/** `AgentWorkshopBridge-0.2.0-linux-arm64` */
export function bridgeBaseName(version, platform) {
  return baseName(version, platform).replace(/^AgentWorkshop-/, 'AgentWorkshopBridge-');
}

/** The bridge archive file name: `.tar.gz` for Linux, `.zip` for the others. */
export function bridgeArchiveName(version, platform) {
  return `${bridgeBaseName(version, platform)}${PLATFORMS[platform].os === 'linux' ? '.tar.gz' : '.zip'}`;
}

function sh(program, args, options = {}) {
  const result = spawnSync(program, args, { encoding: 'utf8', ...options });
  if (result.error) throw new Error(`Could not run ${program}: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`${program} failed (exit code ${result.status}):\n${result.stdout ?? ''}${result.stderr ?? ''}`);
}

/** True when the programs that the tool needs are found. */
export function haveArchiveTools() {
  return ['zip', 'unzip', 'tar'].every((name) => {
    const result = spawnSync(name, name === 'tar' ? ['--version'] : ['-v'], { stdio: 'ignore' });
    return !result.error;
  });
}

export function sha256OfFile(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

/** Makes the archive of one platform from its export folder. Returns the path of the archive. */
export function packagePlatform(platform, { version, inDir, outDir, repoRoot = REPO_ROOT }) {
  const spec = PLATFORMS[platform];
  const exported = join(inDir, platform, spec.file);
  if (!existsSync(exported)) throw new Error(`The export of ${platform} is missing: ${exported}`);
  const name = baseName(version, platform);
  const stage = join(outDir, 'stage');
  const folder = join(stage, name);
  rmSync(folder, { recursive: true, force: true });
  mkdirSync(folder, { recursive: true });

  if (spec.os === 'macos') {
    sh('unzip', ['-q', '-o', exported, '-d', folder]);
    if (!readdirSync(folder).some((entry) => entry.endsWith('.app'))) throw new Error(`The macOS export holds no .app: ${exported}`);
  } else {
    const target = join(folder, spec.file);
    copyFileSync(exported, target);
    if (spec.os === 'linux') chmodSync(target, 0o755);
  }
  for (const file of LICENSE_FILES) copyFileSync(join(repoRoot, file), join(folder, file));
  copyFileSync(join(repoRoot, APP_NOTICES_PATH), join(folder, NOTICE_FILES));

  const archive = join(outDir, archiveName(version, platform));
  rmSync(archive, { force: true });
  // Both programs run inside the stage folder, so the archive holds the folder `name` and not the whole path.
  if (spec.os === 'linux') sh('tar', ['-czf', archive, name], { cwd: stage });
  else sh('zip', ['-r', '-y', '-q', '-X', archive, name], { cwd: stage });
  rmSync(folder, { recursive: true, force: true });
  return archive;
}

/** Makes the archive of the bridge of one platform from its binary. Returns the path of the archive. */
export function packageBridge(platform, { version, bridgeDir, outDir, repoRoot = REPO_ROOT }) {
  const spec = PLATFORMS[platform];
  const binary = join(bridgeDir, platform, bridgeFileName(platform));
  if (!existsSync(binary)) throw new Error(`The bridge binary of ${platform} is missing: ${binary}`);
  const name = bridgeBaseName(version, platform);
  const stage = join(outDir, 'stage');
  const folder = join(stage, name);
  rmSync(folder, { recursive: true, force: true });
  mkdirSync(folder, { recursive: true });

  const target = join(folder, bridgeFileName(platform));
  copyFileSync(binary, target);
  if (spec.os !== 'windows') chmodSync(target, 0o755);
  for (const file of BRIDGE_LICENSE_FILES) copyFileSync(join(repoRoot, file), join(folder, file));
  copyFileSync(join(repoRoot, BRIDGE_NOTICES_PATH), join(folder, NOTICE_FILES));

  const archive = join(outDir, bridgeArchiveName(version, platform));
  rmSync(archive, { force: true });
  if (spec.os === 'linux') sh('tar', ['-czf', archive, name], { cwd: stage });
  else sh('zip', ['-r', '-y', '-q', '-X', archive, name], { cwd: stage });
  rmSync(folder, { recursive: true, force: true });
  return archive;
}

/** Writes SHA256SUMS for the files, in the format of `sha256sum -c`. */
export function writeSums(outDir, files) {
  const lines = files.map((path) => `${sha256OfFile(path)}  ${path.split(/[\\/]/).pop()}`);
  const path = join(outDir, 'SHA256SUMS');
  writeFileSync(path, `${lines.join('\n')}\n`);
  return path;
}

export function packageAll(platforms, options) {
  mkdirSync(options.outDir, { recursive: true });
  const archives = platforms.map((platform) => packagePlatform(platform, options));
  if (options.bridgeDir) archives.push(...platforms.map((platform) => packageBridge(platform, options)));
  rmSync(join(options.outDir, 'stage'), { recursive: true, force: true });
  return { archives, sums: writeSums(options.outDir, archives) };
}

export function parseArgs(argv) {
  const options = { version: null, inDir: join(GODOT_DIR, 'out', 'export'), outDir: join(GODOT_DIR, 'out', 'release'), platform: 'all', bridgeDir: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--version') options.version = argv[++i];
    else if (arg === '--in') options.inDir = argv[++i];
    else if (arg === '--out') options.outDir = argv[++i];
    else if (arg === '--platform') options.platform = argv[++i];
    else if (arg === '--bridge-in') options.bridgeDir = argv[++i];
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (!options.version) throw new Error('Give --version <x.y.z>.');
  if (!SEMVER.test(options.version)) throw new Error(`"${options.version}" is not a version like 1.2.3.`);
  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!haveArchiveTools()) throw new Error('This tool needs zip, unzip and tar in the PATH.');
  const { archives, sums } = packageAll(platformsFor(options.platform), options);
  for (const path of archives) console.log(path);
  console.log(sums);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exitCode = 1;
  }
}
