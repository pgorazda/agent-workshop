// Writes THIRD-PARTY-NOTICES.txt: the name, version, license and license text of every crate that the bridge is built from.
// The licenses of these crates (MIT, Apache-2.0, BSD, Zlib, Unicode) ask that the notice ships with a binary, so the bridge
// archives carry this file (godot/tools/package.mjs).
//
//   node bridge/tools/notices.mjs           write bridge/THIRD-PARTY-NOTICES.txt
//   node bridge/tools/notices.mjs --check   fail when the file is not up to date with Cargo.lock (CI runs this)
//
// It reads the license files from the crate sources that cargo has downloaded, so run `cargo fetch --locked` first.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BRIDGE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
export const NOTICES_PATH = join(BRIDGE_DIR, 'THIRD-PARTY-NOTICES.txt');

const LICENSE_FILE = /^(licen[cs]e|copying|notice|unlicense)([-_.].*)?$/i;

/** The license files of a crate folder, in name order. A folder named `LICENSES` is read one level deep. */
export function licenseFiles(dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.isFile() && LICENSE_FILE.test(entry.name)) found.push(join(dir, entry.name));
    if (entry.isDirectory() && /^licenses?$/i.test(entry.name)) {
      for (const inner of readdirSync(join(dir, entry.name)).sort()) found.push(join(dir, entry.name, inner));
    }
  }
  return found;
}

export function packages() {
  const out = execFileSync('cargo', ['metadata', '--format-version', '1', '--locked'], {
    cwd: BRIDGE_DIR,
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
  const metadata = JSON.parse(out);
  const own = new Set(metadata.workspace_members);
  return metadata.packages
    .filter((p) => !own.has(p.id))
    .sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version));
}

export function noticesText() {
  const lines = [
    'Third-party notices for agent-workshop-bridge',
    '',
    'The bridge is built from the crates below. Each one is used under the license named for it.',
    'The license texts follow the list. A text that many crates share is printed once.',
    '',
    'Crates',
    '------',
  ];
  const texts = new Map(); // license text -> the crates that carry it
  const bare = [];
  for (const pkg of packages()) {
    const dir = dirname(pkg.manifest_path);
    lines.push(`${pkg.name} ${pkg.version}: ${pkg.license ?? 'see the license files'}${pkg.repository ? ` (${pkg.repository})` : ''}`);
    const files = existsSync(dir) ? licenseFiles(dir) : [];
    if (files.length === 0) bare.push(`${pkg.name} ${pkg.version} (${pkg.license ?? 'unknown license'})`);
    for (const file of files) {
      const text = readFileSync(file, 'utf8').replace(/\r\n/g, '\n').trim();
      if (!texts.has(text)) texts.set(text, []);
      texts.get(text).push(`${pkg.name} ${pkg.version}`);
    }
  }
  if (bare.length > 0) {
    lines.push('', 'These crates ship no license file. Their license is the one named above: see their repositories.');
    for (const name of bare) lines.push(`  ${name}`);
  }
  lines.push('', 'License texts', '-------------');
  for (const [text, users] of [...texts].sort((x, y) => y[1].length - x[1].length || x[0].localeCompare(y[0]))) {
    lines.push('', '='.repeat(78), `Used by: ${[...new Set(users)].join(', ')}`, '', text);
  }
  return `${lines.join('\n')}\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const text = noticesText();
  if (process.argv.includes('--check')) {
    const current = existsSync(NOTICES_PATH) ? readFileSync(NOTICES_PATH, 'utf8') : '';
    if (current !== text) {
      console.error('bridge/THIRD-PARTY-NOTICES.txt is out of date: run node bridge/tools/notices.mjs');
      process.exit(1);
    }
    console.log('THIRD-PARTY-NOTICES.txt is up to date');
  } else {
    writeFileSync(NOTICES_PATH, text);
    console.log(`wrote ${NOTICES_PATH} (${text.length} bytes)`);
  }
}
