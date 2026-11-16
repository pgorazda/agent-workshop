// Tests the parts of get-godot.mjs that need no network. The download itself is not run here.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HASHES, assetFor, getGodot, sha512Of, siteUrl } from './get-godot.mjs';
import { downloadedEditorPath, pinnedVersion, resolveGodot } from './godot-path.mjs';

test('GODOT_VERSION has a pinned hash for each desktop platform', () => {
  const version = pinnedVersion();
  assert.match(version, /^4\.7\.\d+$/);
  assert.ok(HASHES[version], `no hashes for ${version}`);
  for (const key of ['win32-x64', 'linux-x64', 'darwin-x64', 'darwin-arm64']) {
    const [platform, arch] = key.split('-');
    const asset = assetFor(version, platform, arch);
    assert.match(asset.sha512, /^[0-9a-f]{128}$/, key);
    assert.ok(asset.file.startsWith(`Godot_v${version}-stable_`), key);
  }
});

test('the download goes to godotengine.org, with the version and the archive name in the address', () => {
  const asset = assetFor('4.7.2', 'win32', 'x64');
  const url = new URL(siteUrl('4.7.2', asset.slug));
  assert.equal(url.hostname, 'downloads.godotengine.org');
  assert.equal(url.searchParams.get('version'), '4.7.2');
  assert.equal(url.searchParams.get('slug'), 'win64.exe.zip');
});

test('an unknown platform or version has no hash, so there is no download', () => {
  assert.throws(() => assetFor('4.7.2', 'freebsd', 'x64'), /No pinned hash/);
  assert.throws(() => assetFor('9.9.9', 'win32', 'x64'), /No pinned hash/);
});

test('sha512Of gives the SHA-512 of the bytes', () => {
  assert.equal(
    sha512Of(Buffer.from('abc')),
    'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
  );
});

test('when GODOT is set, nothing is downloaded and the path is used', async () => {
  const logs = [];
  const path = await getGodot({ env: { GODOT: 'some/editor' }, log: (line) => logs.push(line) });
  assert.equal(path, 'some/editor');
  assert.match(logs.join('\n'), /not downloading/);
});

test('resolveGodot uses GODOT, and says what to do when there is no editor', () => {
  assert.throws(() => resolveGodot({ GODOT: 'definitely/not/here' }), /does not exist/);
  assert.ok(downloadedEditorPath('4.7.2', 'win32').endsWith('Godot_v4.7.2-stable_win64_console.exe'));
  assert.ok(downloadedEditorPath('4.7.2', 'linux').endsWith('Godot_v4.7.2-stable_linux.x86_64'));
});
