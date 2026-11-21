// Tests the packaging tool (release workflow):  node --test
// It packs small fake exports. The archive tests are skipped when zip, unzip or tar is not installed (a plain Windows shell).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { PLATFORMS } from './export.mjs';
import { APP_NOTICES_PATH, BRIDGE_NOTICES_PATH, LICENSE_FILES, REPO_ROOT, archiveName, baseName, bridgeArchiveName, bridgeFileName, haveArchiveTools, packageAll, parseArgs, sha256OfFile } from './package.mjs';

const tools = haveArchiveTools();

test('the names say the version, the system and the architecture', () => {
  assert.equal(baseName('0.2.0', 'windows'), 'AgentWorkshop-0.2.0-windows-x86_64');
  assert.equal(baseName('0.2.0', 'windows-arm64'), 'AgentWorkshop-0.2.0-windows-arm64');
  assert.equal(archiveName('0.2.0', 'linux'), 'AgentWorkshop-0.2.0-linux-x86_64.tar.gz');
  assert.equal(archiveName('0.2.0', 'linux-arm64'), 'AgentWorkshop-0.2.0-linux-arm64.tar.gz');
  assert.equal(archiveName('0.2.0', 'macos'), 'AgentWorkshop-0.2.0-macos-universal.zip');
  assert.throws(() => baseName('0.2', 'linux'), /not a version/);
  assert.throws(() => baseName('0.2.0', 'amiga'), /Unknown platform/);
  const names = Object.keys(PLATFORMS).map((p) => archiveName('1.0.0', p));
  assert.equal(new Set(names).size, names.length, 'every platform has its own file name');
});

test('the bridge archives have names of their own', () => {
  assert.equal(bridgeArchiveName('0.2.0', 'windows'), 'AgentWorkshopBridge-0.2.0-windows-x86_64.zip');
  assert.equal(bridgeArchiveName('0.2.0', 'windows-arm64'), 'AgentWorkshopBridge-0.2.0-windows-arm64.zip');
  assert.equal(bridgeArchiveName('0.2.0', 'linux'), 'AgentWorkshopBridge-0.2.0-linux-x86_64.tar.gz');
  assert.equal(bridgeArchiveName('0.2.0', 'linux-arm64'), 'AgentWorkshopBridge-0.2.0-linux-arm64.tar.gz');
  assert.equal(bridgeArchiveName('0.2.0', 'macos'), 'AgentWorkshopBridge-0.2.0-macos-universal.zip');
  assert.equal(bridgeFileName('windows'), 'agent-workshop-bridge.exe');
  assert.equal(bridgeFileName('windows-arm64'), 'agent-workshop-bridge.exe');
  assert.equal(bridgeFileName('macos'), 'agent-workshop-bridge');
  assert.throws(() => bridgeFileName('amiga'), /Unknown platform/);
  const all = Object.keys(PLATFORMS).flatMap((p) => [archiveName('1.0.0', p), bridgeArchiveName('1.0.0', p)]);
  assert.equal(new Set(all).size, all.length, 'no app and no bridge share a file name');
});

test('the command line', () => {
  assert.equal(parseArgs(['--version', '1.2.3']).platform, 'all');
  assert.equal(parseArgs(['--version', '1.2.3', '--platform', 'macos']).platform, 'macos');
  assert.throws(() => parseArgs([]), /--version/);
  assert.throws(() => parseArgs(['--version', 'v1.2.3']), /not a version/);
  assert.throws(() => parseArgs(['--version', '1.2.3', '--zip']), /Unknown option/);
  assert.equal(parseArgs(['--version', '1.2.3']).bridgeDir, null);
  assert.equal(parseArgs(['--version', '1.2.3', '--bridge-in', 'bin']).bridgeDir, 'bin');
});

test('the license files and the notices exist in the repository', () => {
  for (const file of [...LICENSE_FILES, APP_NOTICES_PATH, BRIDGE_NOTICES_PATH]) assert.ok(existsSync(join(REPO_ROOT, file)), file);
});

test('the notices of the app are those of the pinned Godot version', () => {
  const version = readFileSync(join(REPO_ROOT, 'godot', 'GODOT_VERSION'), 'utf8').trim();
  const notices = readFileSync(join(REPO_ROOT, APP_NOTICES_PATH), 'utf8');
  assert.ok(notices.includes(`Godot Engine ${version}`), `the notices name Godot ${version}: run the tool tools/licenses.gd`);
  assert.ok(notices.includes('Permission is hereby granted, free of charge'), 'the engine license text is in it');
});

/** Fake exports: a file for Windows and Linux, a zip with an .app for macOS. */
function fakeExports(root) {
  for (const [platform, spec] of Object.entries(PLATFORMS)) {
    const folder = join(root, platform);
    mkdirSync(folder, { recursive: true });
    if (spec.os === 'macos') {
      const app = join(root, 'macos-src', 'AgentWorkshop.app', 'Contents', 'MacOS');
      mkdirSync(app, { recursive: true });
      writeFileSync(join(app, 'AgentWorkshop'), 'fake mac executable');
      const zip = spawnSync('zip', ['-r', '-q', join(folder, spec.file), 'AgentWorkshop.app'], { cwd: join(root, 'macos-src') });
      assert.equal(zip.status, 0);
    } else {
      writeFileSync(join(folder, spec.file), `fake ${platform} app`);
    }
  }
}

test('all five platforms are packed, with the licenses, the executable flag and a SHA256SUMS that matches', { skip: !tools && 'zip, unzip or tar is missing' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-package-'));
  try {
    const inDir = join(root, 'export');
    const outDir = join(root, 'release');
    fakeExports(inDir);
    const { archives, sums } = packageAll(Object.keys(PLATFORMS), { version: '0.2.0', inDir, outDir });
    assert.equal(archives.length, 5);
    assert.deepEqual(readdirSync(outDir).sort(), [...archives.map((a) => a.split(/[\\/]/).pop()), 'SHA256SUMS'].sort(), 'no stage folder is left');

    // SHA256SUMS: one line per archive, the right hash
    const lines = readFileSync(sums, 'utf8').trim().split('\n');
    assert.equal(lines.length, 5);
    for (const line of lines) {
      const [hash, name] = line.split('  ');
      assert.equal(hash, sha256OfFile(join(outDir, name)), name);
    }

    // a zip: the folder, the app and the licenses
    const listing = spawnSync('unzip', ['-Z1', join(outDir, 'AgentWorkshop-0.2.0-windows-arm64.zip')], { encoding: 'utf8' }).stdout.split('\n');
    for (const entry of ['AgentWorkshop-0.2.0-windows-arm64/AgentWorkshop.exe', 'AgentWorkshop-0.2.0-windows-arm64/LICENSE', 'AgentWorkshop-0.2.0-windows-arm64/LICENSE-ASSETS', 'AgentWorkshop-0.2.0-windows-arm64/THIRD-PARTY-NOTICES.txt']) {
      assert.ok(listing.includes(entry), entry);
    }
    const mac = spawnSync('unzip', ['-Z1', join(outDir, 'AgentWorkshop-0.2.0-macos-universal.zip')], { encoding: 'utf8' }).stdout;
    assert.match(mac, /AgentWorkshop-0\.2\.0-macos-universal\/AgentWorkshop\.app\/Contents\/MacOS\/AgentWorkshop/);

    // a tar.gz: the app keeps its executable flag
    const unpacked = join(root, 'unpacked');
    mkdirSync(unpacked);
    assert.equal(spawnSync('tar', ['-xzf', join(outDir, 'AgentWorkshop-0.2.0-linux-arm64.tar.gz'), '-C', unpacked]).status, 0);
    const app = join(unpacked, 'AgentWorkshop-0.2.0-linux-arm64', 'AgentWorkshop.arm64');
    assert.ok(statSync(app).mode & 0o100, 'the Linux app is executable');
    assert.ok(existsSync(join(unpacked, 'AgentWorkshop-0.2.0-linux-arm64', 'LICENSE-ASSETS')));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

/** Fake bridge binaries, one for each platform. */
function fakeBridges(root) {
  for (const platform of Object.keys(PLATFORMS)) {
    mkdirSync(join(root, platform), { recursive: true });
    writeFileSync(join(root, platform, bridgeFileName(platform)), `fake bridge ${platform}`);
  }
}

test('with --bridge-in each platform also gets a bridge archive with the binary and the license only', { skip: !tools && 'zip, unzip or tar is missing' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-package-'));
  try {
    const inDir = join(root, 'export');
    const bridgeDir = join(root, 'bridge');
    const outDir = join(root, 'release');
    fakeExports(inDir);
    fakeBridges(bridgeDir);
    const { archives, sums } = packageAll(Object.keys(PLATFORMS), { version: '0.2.0', inDir, bridgeDir, outDir });
    assert.equal(archives.length, 10, 'five apps and five bridges');
    assert.deepEqual(readdirSync(outDir).sort(), [...archives.map((a) => a.split(/[\\/]/).pop()), 'SHA256SUMS'].sort());
    const lines = readFileSync(sums, 'utf8').trim().split('\n');
    assert.equal(lines.length, 10);
    for (const line of lines) {
      const [hash, name] = line.split('  ');
      assert.equal(hash, sha256OfFile(join(outDir, name)), name);
    }

    // a zip: the folder, the binary and the license, and no license of the art
    const zipName = 'AgentWorkshopBridge-0.2.0-windows-arm64';
    const listing = spawnSync('unzip', ['-Z1', join(outDir, `${zipName}.zip`)], { encoding: 'utf8' }).stdout.split('\n').filter(Boolean);
    assert.deepEqual(listing.sort(), [`${zipName}/`, `${zipName}/LICENSE`, `${zipName}/THIRD-PARTY-NOTICES.txt`, `${zipName}/agent-workshop-bridge.exe`].sort());

    // the macOS zip keeps the executable flag
    const macDir = join(root, 'mac');
    mkdirSync(macDir);
    assert.equal(spawnSync('unzip', ['-q', join(outDir, 'AgentWorkshopBridge-0.2.0-macos-universal.zip'), '-d', macDir]).status, 0);
    assert.ok(statSync(join(macDir, 'AgentWorkshopBridge-0.2.0-macos-universal', 'agent-workshop-bridge')).mode & 0o100, 'the macOS binary is executable');

    // a tar.gz: the binary keeps its executable flag
    const unpacked = join(root, 'unpacked');
    mkdirSync(unpacked);
    assert.equal(spawnSync('tar', ['-xzf', join(outDir, 'AgentWorkshopBridge-0.2.0-linux-x86_64.tar.gz'), '-C', unpacked]).status, 0);
    const binary = join(unpacked, 'AgentWorkshopBridge-0.2.0-linux-x86_64', 'agent-workshop-bridge');
    assert.ok(statSync(binary).mode & 0o100, 'the Linux binary is executable');
    assert.equal(readFileSync(binary, 'utf8'), 'fake bridge linux');
    assert.ok(!existsSync(join(unpacked, 'AgentWorkshopBridge-0.2.0-linux-x86_64', 'LICENSE-ASSETS')), 'the bridge has no art license');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a missing bridge binary is an error that names the file', { skip: !tools && 'zip, unzip or tar is missing' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-package-'));
  try {
    const inDir = join(root, 'export');
    fakeExports(inDir);
    assert.throws(
      () => packageAll(['linux'], { version: '0.2.0', inDir, bridgeDir: join(root, 'none'), outDir: join(root, 'out') }),
      /The bridge binary of linux is missing/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a missing export is an error that names the file', { skip: !tools && 'zip, unzip or tar is missing' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-package-'));
  try {
    assert.throws(() => packageAll(['linux'], { version: '0.2.0', inDir: join(root, 'none'), outDir: join(root, 'out') }), /The export of linux is missing/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
