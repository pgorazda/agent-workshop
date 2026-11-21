#!/usr/bin/env node
// Keeps the version number of Agent Workshop in step in every place that holds it, and checks a release tag.
//
//   node godot/tools/version.mjs show              # print the version, or fail when the places disagree
//   node godot/tools/version.mjs check [v0.2.0]    # fail when the places disagree, or when they do not match the tag
//   node godot/tools/version.mjs bump 0.2.0        # write the version into every place
//
// `check` prints `version=<x.y.z>` and `prerelease=<true|false>` on standard output, so a workflow can append the lines to
// $GITHUB_OUTPUT. Errors go to standard error. A tag is `v<x.y.z>`, with an optional suffix such as `-alpha.1`. A tag with a
// suffix is a pre-release. The suffix is not written into any file: the files hold the plain `x.y.z`, because the Windows and
// macOS version fields take numbers only.
//
// The places: bridge/Cargo.toml, bridge/Cargo.lock (the entry of the bridge), godot/project.godot and godot/export_presets.cfg
// (the Windows file and product version, the macOS short version and version).

import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = fileURLToPath(new URL('../..', import.meta.url));
export const SEMVER = /^\d+\.\d+\.\d+$/;
export const TAG = /^v(\d+\.\d+\.\d+)(-[0-9A-Za-z][0-9A-Za-z.-]*)?$/;

const windowsFour = { format: (v) => `${v}.0`, parse: (raw) => raw.replace(/\.0$/, '') };
const plain = { format: (v) => v, parse: (raw) => raw };

/** Each place: a file, a label, a pattern with three groups (text before, the version, text after) and how the value is written. */
export const PLACES = [
  { file: 'bridge/Cargo.toml', label: 'bridge/Cargo.toml', pattern: /^(version = ")([^"]+)(")/m, ...plain },
  { file: 'bridge/Cargo.lock', label: 'bridge/Cargo.lock (agent-workshop-bridge)', pattern: /^(name = "agent-workshop-bridge"\nversion = ")([^"]+)(")/m, ...plain },
  { file: 'godot/project.godot', label: 'godot/project.godot', pattern: /^(config\/version=")([^"]+)(")/m, ...plain },
  { file: 'godot/export_presets.cfg', label: 'export_presets.cfg (Windows file version)', pattern: /^(application\/file_version=")([^"]+)(")/m, ...windowsFour },
  { file: 'godot/export_presets.cfg', label: 'export_presets.cfg (Windows product version)', pattern: /^(application\/product_version=")([^"]+)(")/m, ...windowsFour },
  { file: 'godot/export_presets.cfg', label: 'export_presets.cfg (macOS short version)', pattern: /^(application\/short_version=")([^"]+)(")/m, ...plain },
  { file: 'godot/export_presets.cfg', label: 'export_presets.cfg (macOS version)', pattern: /^(application\/version=")([^"]+)(")/m, ...plain },
];

/** A place can appear more than once in a file (the Windows presets for x86_64 and for ARM64), so a pattern matches every time. */
const everywhere = (pattern) => new RegExp(pattern.source, `${pattern.flags.replace('g', '')}g`);

/** The version in each place: [{ label, value }]. Throws when a place is not found. */
export function readVersions(root = ROOT) {
  return PLACES.flatMap((place) => {
    const matches = [...readFileSync(join(root, place.file), 'utf8').matchAll(everywhere(place.pattern))];
    if (matches.length === 0) throw new Error(`No version found in ${place.label}.`);
    return matches.map((match, i) => ({ label: matches.length > 1 ? `${place.label} #${i + 1}` : place.label, value: place.parse(match[2]) }));
  });
}

/** The one version of all places. Throws and lists the places when they disagree, or when `expected` is given and differs. */
export function checkVersions({ root = ROOT, expected = null } = {}) {
  const found = readVersions(root);
  const values = new Set(found.map((f) => f.value));
  if (values.size > 1 || (expected !== null && !values.has(expected))) {
    const lines = found.map((f) => `  ${f.label}: ${f.value}`).join('\n');
    const want = expected === null ? '' : `\nThe tag says ${expected}.`;
    throw new Error(`The version is not the same in all places.${want}\n${lines}\nRun: node godot/tools/version.mjs bump <x.y.z>`);
  }
  const [version] = values;
  if (!SEMVER.test(version)) throw new Error(`"${version}" is not a version like 1.2.3.`);
  return version;
}

/** Splits a tag such as v0.2.0 or v0.2.0-alpha.1. */
export function parseTag(tag) {
  const match = TAG.exec(tag);
  if (!match) throw new Error(`"${tag}" is not a release tag. Use v<x.y.z>, for example v0.2.0 or v0.2.0-alpha.1.`);
  return { version: match[1], prerelease: match[2] !== undefined };
}

/** Writes the version into every place. Returns the files that changed. */
export function bumpVersions(version, root = ROOT) {
  if (!SEMVER.test(version)) throw new Error(`"${version}" is not a version like 1.2.3.`);
  const changed = new Set();
  for (const place of PLACES) {
    const path = join(root, place.file);
    const text = readFileSync(path, 'utf8');
    const next = text.replace(everywhere(place.pattern), (_all, before, _old, after) => `${before}${place.format(version)}${after}`);
    if (next === text) continue;
    writeFileSync(path, next);
    changed.add(place.file);
  }
  checkVersions({ root, expected: version });
  return [...changed];
}

function main(argv) {
  const [command, argument] = argv;
  if (command === 'show') {
    console.log(checkVersions());
  } else if (command === 'check') {
    if (argument === undefined) {
      console.log(`version=${checkVersions()}`);
      console.log('prerelease=false');
    } else {
      const tag = parseTag(argument);
      console.log(`version=${checkVersions({ expected: tag.version })}`);
      console.log(`prerelease=${tag.prerelease}`);
    }
  } else if (command === 'bump') {
    if (argument === undefined) throw new Error('Give the new version: node godot/tools/version.mjs bump 0.2.0');
    const changed = bumpVersions(argument.replace(/^v/, ''));
    console.log(`Version ${argument.replace(/^v/, '')} is set. Changed: ${changed.join(', ') || 'nothing'}`);
  } else {
    throw new Error('Use: show | check [tag] | bump <x.y.z>');
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exitCode = 1;
  }
}
