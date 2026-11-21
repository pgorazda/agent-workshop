// Downloads the pinned Godot editor from godotengine.org into godot/.editor/ (a git-ignored folder).
// It checks the SHA-512 hash of the archive before it unpacks it.
//
//   node tools/get-godot.mjs
//
// If the environment variable GODOT is set, the script does nothing: you use your own editor.
//
// The hashes below are the official ones: the file SHA512-SUMS.txt of the release 4.7.2-stable in
// https://github.com/godotengine/godot-builds. When GODOT_VERSION changes, change this table in the same step.

import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, rmSync } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { EDITOR_DIR, downloadedEditorPath, pinnedVersion } from './godot-path.mjs';

// Standard build (not .NET). Key: the version, then the platform and architecture.
export const HASHES = {
  '4.7.2': {
    'win32-x64': {
      slug: 'win64.exe.zip',
      sha512:
        '83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993',
    },
    'linux-x64': {
      slug: 'linux.x86_64.zip',
      sha512:
        '9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65',
    },
    'darwin-x64': {
      slug: 'macos.universal.zip',
      sha512:
        '38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca',
    },
    'darwin-arm64': {
      slug: 'macos.universal.zip',
      sha512:
        '38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca',
    },
  },
};

/** The archive name and hash for a version, platform and architecture. Throws when there is none. */
export function assetFor(version, platform = process.platform, arch = process.arch) {
  const entry = HASHES[version]?.[`${platform}-${arch}`];
  if (!entry) throw new Error(`No pinned hash for Godot ${version} on ${platform}-${arch}. Set GODOT instead.`);
  return { ...entry, file: `Godot_v${version}-stable_${entry.slug}` };
}

/** The official download page of godotengine.org. It redirects to the release file. */
export function siteUrl(version, slug) {
  const platform = slug.startsWith('win') ? 'windows.64' : slug.startsWith('macos') ? 'macos.universal' : 'linux.64';
  return `https://downloads.godotengine.org/?version=${version}&flavor=stable&slug=${slug}&platform=${platform}`;
}

export function sha512Of(buffer) {
  return createHash('sha512').update(buffer).digest('hex');
}

async function sha512OfFile(path) {
  const hash = createHash('sha512');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

function unpack(archive, folder) {
  // bsdtar (Windows 10 and later, macOS) reads zip files. Linux often has unzip only.
  const tar = spawnSync('tar', ['-xf', archive, '-C', folder], { stdio: 'inherit' });
  if (tar.status === 0) return;
  const unzip = spawnSync('unzip', ['-o', archive, '-d', folder], { stdio: 'inherit' });
  if (unzip.status !== 0) throw new Error('Could not unpack the archive: neither "tar" nor "unzip" worked.');
}

export async function getGodot({ env = process.env, log = console.log } = {}) {
  if (env.GODOT) {
    log('GODOT is set: not downloading. The scripts use that editor.');
    return env.GODOT;
  }
  const version = pinnedVersion();
  const target = downloadedEditorPath(version);
  if (existsSync(target)) {
    log(`Godot ${version} is already in godot/.editor/.`);
    return target;
  }
  const asset = assetFor(version);
  const folder = join(EDITOR_DIR, version);
  mkdirSync(folder, { recursive: true });
  const archive = join(folder, asset.file);
  const url = siteUrl(version, asset.slug);
  log(`Downloading ${asset.file} from godotengine.org ...`);
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok || !response.body) throw new Error(`Download failed: HTTP ${response.status} for ${url}`);
  await pipeline(Readable.fromWeb(response.body), createWriteStream(archive));
  const actual = await sha512OfFile(archive);
  if (actual !== asset.sha512) {
    rmSync(archive, { force: true });
    throw new Error(`Hash mismatch for ${asset.file}.\n  expected ${asset.sha512}\n  actual   ${actual}\nThe file was deleted.`);
  }
  log('Hash is correct. Unpacking ...');
  unpack(archive, folder);
  rmSync(archive, { force: true });
  if (!existsSync(target)) throw new Error(`The archive did not contain the expected editor file: ${target}`);
  log(`Done: ${target}`);
  return target;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  getGodot().catch((err) => {
    console.error(`error: ${err.message}`);
    process.exitCode = 1;
  });
}
