// Finds, builds and starts the Rust bridge for the tools and tests of the repository (godot/tools, adapters/test).
//
// The binary is `agent-workshop-bridge`. The order of the search:
//   1. the environment variable ARENA_BRIDGE_BIN (a path to the binary);
//   2. the debug build of the crate: <crate>/target/debug/agent-workshop-bridge (.exe on Windows).
// `ensureBridgeBuilt()` runs `cargo build` for the second case when the binary is missing or when no environment variable is set.
// The path of a binary on a computer never goes into the repository.

import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** The folder of the Rust crate (the parent of this folder). */
export const BRIDGE_CRATE = fileURLToPath(new URL('..', import.meta.url));
const EXE = process.platform === 'win32' ? '.exe' : '';

/** The path of the bridge binary, or throws an error that says what to do. */
export function bridgeBinary(env = process.env) {
  if (env.ARENA_BRIDGE_BIN) {
    if (!existsSync(env.ARENA_BRIDGE_BIN)) throw new Error(`ARENA_BRIDGE_BIN is set, but the file does not exist: ${env.ARENA_BRIDGE_BIN}`);
    return env.ARENA_BRIDGE_BIN;
  }
  const built = join(BRIDGE_CRATE, 'target', 'debug', `agent-workshop-bridge${EXE}`);
  if (existsSync(built)) return built;
  throw new Error(`No bridge binary found. Run "cargo build" in ${BRIDGE_CRATE}, or set ARENA_BRIDGE_BIN.`);
}

/** Builds the debug binary (a quick no-op when it is up to date), unless ARENA_BRIDGE_BIN names a binary. */
export function ensureBridgeBuilt(env = process.env) {
  if (env.ARENA_BRIDGE_BIN) return bridgeBinary(env);
  const result = spawnSync('cargo', ['build', '--quiet'], { cwd: BRIDGE_CRATE, stdio: 'inherit' });
  if (result.error || result.status !== 0) throw new Error(`"cargo build" failed in ${BRIDGE_CRATE}`);
  return bridgeBinary(env);
}

/**
 * Starts `agent-workshop-bridge serve` and waits until it listens. `port` 0 (the default) takes a free port.
 * Returns { port, child, stop }. `stop()` ends the process and waits for it.
 */
export function startBridge({ port = 0, args = [], env = process.env } = {}) {
  const clean = { ...env };
  for (const name of ['ARENA_HOST', 'ARENA_PORT', 'ARENA_REDACT_TARGETS']) delete clean[name];
  const child = spawn(bridgeBinary(env), ['serve', '--port', String(port), ...args], { stdio: ['ignore', 'pipe', 'pipe'], env: clean });
  let output = '';
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`the bridge did not start in 10 s:\n${output}`)), 10000);
    const onData = (chunk) => {
      output += chunk.toString('utf8');
      const match = /listening on http:\/\/[^:]+:(\d+)/.exec(output);
      if (match) {
        clearTimeout(timer);
        resolve({
          port: Number(match[1]),
          child,
          stop: () =>
            new Promise((done) => {
              if (child.exitCode !== null || child.signalCode !== null) return done();
              child.once('exit', () => done());
              child.kill();
            }),
        });
      }
    };
    child.stdout.on('data', onData);
    child.stderr.on('data', (chunk) => (output += chunk.toString('utf8')));
    child.on('error', (err) => (clearTimeout(timer), reject(err)));
    child.on('exit', (code) => (clearTimeout(timer), reject(new Error(`the bridge ended with code ${code} before it listened:\n${output}`))));
  });
}
