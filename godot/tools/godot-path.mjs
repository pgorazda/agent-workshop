// Finds the Godot editor for the scripts in this folder.
//
// Order: 1. the environment variable GODOT (a path to the editor or its console build);
//        2. the copy that get-godot.mjs downloaded into godot/.editor/.
// The path of an editor on a computer never goes into the repository.

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const GODOT_DIR = fileURLToPath(new URL('..', import.meta.url));
export const EDITOR_DIR = join(GODOT_DIR, '.editor');

/** The pinned version, for example "4.7.2". */
export function pinnedVersion() {
  return readFileSync(join(GODOT_DIR, 'GODOT_VERSION'), 'utf8').trim();
}

/** Where get-godot.mjs puts the editor executable for a platform and version. */
export function downloadedEditorPath(version = pinnedVersion(), platform = process.platform) {
  const base = join(EDITOR_DIR, version);
  if (platform === 'win32') return join(base, `Godot_v${version}-stable_win64_console.exe`);
  if (platform === 'darwin') return join(base, 'Godot.app', 'Contents', 'MacOS', 'Godot');
  return join(base, `Godot_v${version}-stable_linux.x86_64`);
}

/** The editor path, or throws an error that says what to do. */
export function resolveGodot(env = process.env) {
  if (env.GODOT) {
    if (!existsSync(env.GODOT)) throw new Error(`GODOT is set, but the file does not exist: ${env.GODOT}`);
    return env.GODOT;
  }
  const downloaded = downloadedEditorPath();
  if (existsSync(downloaded)) return downloaded;
  throw new Error(
    'No Godot editor found. Set the environment variable GODOT to the editor, ' +
      'or run "node tools/get-godot.mjs" in godot/ to download version ' +
      `${pinnedVersion()}.`,
  );
}
