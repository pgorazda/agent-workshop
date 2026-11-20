// Tests the packaging tool (release workflow):  node --test
// It packs small fake exports. The archive tests are skipped when zip, unzip or tar is not installed (a plain Windows shell).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { PLATFORMS } from './export.mjs';
import { LICENSE_FILES, REPO_ROOT, archiveName, baseName, haveArchiveTools, packageAll, parseArgs, sha256OfFile } from './package.mjs';

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

test('the command line', () => {
  assert.equal(parseArgs(['--version', '1.2.3']).platform, 'all');
  assert.equal(parseArgs(['--version', '1.2.3', '--platform', 'macos']).platform, 'macos');
  assert.throws(() => parseArgs([]), /--version/);
  assert.throws(() => parseArgs(['--version', 'v1.2.3']), /not a version/);
  assert.throws(() => parseArgs(['--version', '1.2.3', '--zip']), /Unknown option/);
});

test('the license files exist in the repository', () => {
  for (const file of LICENSE_FILES) assert.ok(existsSync(join(REPO_ROOT, file)), file);
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
    for (const entry of ['AgentWorkshop-0.2.0-windows-arm64/AgentWorkshop.exe', 'AgentWorkshop-0.2.0-windows-arm64/LICENSE', 'AgentWorkshop-0.2.0-windows-arm64/LICENSE-ASSETS']) {
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

test('a missing export is an error that names the file', { skip: !tools && 'zip, unzip or tar is missing' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-package-'));
  try {
    assert.throws(() => packageAll(['linux'], { version: '0.2.0', inDir: join(root, 'none'), outDir: join(root, 'out') }), /The export of linux is missing/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
