// Tests the version tool (release workflow):  node --test
// It works on a copy of the real files, so the real files are never changed.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { PLACES, ROOT, bumpVersions, checkVersions, parseTag, readVersions } from './version.mjs';

function copyOfFiles() {
  const root = mkdtempSync(join(tmpdir(), 'agent-workshop-version-'));
  for (const file of new Set(PLACES.map((p) => p.file))) {
    mkdirSync(dirname(join(root, file)), { recursive: true });
    cpSync(join(ROOT, file), join(root, file));
  }
  return root;
}

test('the real files hold one version, a plain x.y.z', () => {
  const version = checkVersions();
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.ok(readVersions().length > PLACES.length, 'the Windows presets for x86_64 and ARM64 count twice');
});

test('a tag is v<x.y.z> with an optional suffix, and a suffix makes a pre-release', () => {
  assert.deepEqual(parseTag('v1.2.3'), { version: '1.2.3', prerelease: false });
  assert.deepEqual(parseTag('v0.2.0-alpha.1'), { version: '0.2.0', prerelease: true });
  assert.deepEqual(parseTag('v10.0.1-rc1'), { version: '10.0.1', prerelease: true });
  for (const bad of ['1.2.3', 'v1.2', 'v1.2.3.4', 'v1.2.3-', 'v1.2.3+build', 'release-1', 'v1.2.3 ', 'vx.y.z']) {
    assert.throws(() => parseTag(bad), /not a release tag/, bad);
  }
});

test('a bump writes the version into every place, and the check then passes for that version only', () => {
  const root = copyOfFiles();
  try {
    const changed = bumpVersions('9.8.7', root);
    assert.ok(changed.length > 0);
    assert.equal(checkVersions({ root, expected: '9.8.7' }), '9.8.7');
    assert.throws(() => checkVersions({ root, expected: '9.8.6' }), /The tag says 9\.8\.6/);
    const presets = readFileSync(join(root, 'godot/export_presets.cfg'), 'utf8');
    assert.equal(presets.match(/^application\/file_version="9\.8\.7\.0"$/gm).length, 2, 'both Windows presets');
    assert.equal(presets.match(/^application\/product_version="9\.8\.7\.0"$/gm).length, 2);
    assert.match(presets, /^application\/short_version="9\.8\.7"$/m);
    assert.match(presets, /^application\/version="9\.8\.7"$/m);
    assert.match(readFileSync(join(root, 'godot/project.godot'), 'utf8'), /^config\/version="9\.8\.7"$/m);
    const lock = readFileSync(join(root, 'bridge/Cargo.lock'), 'utf8');
    assert.match(lock, /^name = "agent-workshop-bridge"\nversion = "9\.8\.7"$/m);
    assert.equal(lock.match(/^version = "9\.8\.7"$/gm).length, 1, 'no other package in the lock file changes');
    assert.match(readFileSync(join(root, 'bridge/Cargo.toml'), 'utf8'), /^version = "9\.8\.7"$/m);
    assert.deepEqual(bumpVersions('9.8.7', root), [], 'a second bump to the same version changes nothing');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('the check names the places that disagree', () => {
  const root = copyOfFiles();
  try {
    const path = join(root, 'godot/project.godot');
    writeFileSync(path, readFileSync(path, 'utf8').replace(/^config\/version="[^"]+"/m, 'config/version="0.0.1"'));
    assert.throws(() => checkVersions({ root }), /godot\/project\.godot: 0\.0\.1/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a bump refuses a version that is not x.y.z', () => {
  const root = copyOfFiles();
  try {
    for (const bad of ['1.2', '1.2.3-alpha', 'latest', '']) assert.throws(() => bumpVersions(bad, root), /not a version/, bad);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
