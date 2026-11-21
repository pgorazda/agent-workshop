// A replayed session through the real bridge into the real client (phase G-8).
//
//   node --test        (from godot/; set GODOT, see README.md)
//
// The test starts a real bridge on a free port and runs the Godot client headless with `--trace` (it prints "[trace] <who>: <station>" each
// time a penguin begins to visit a station). Then it runs the real replay command of the bridge (`agent-workshop-bridge replay`) on the real Claude Code example, and compares what the client printed with the behaviour trace fixture
// `test/fixtures/expected-trace.json` ("claude-code-fixture": the same example through the adapter, the real Claude Code order). The client
// plays in real time, so the test takes the time that the penguin needs (about 15 s for each run).

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { bridgeBinary, ensureBridgeBuilt, startBridge } from '../../bridge/tools/bridge-binary.mjs';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';
import { importProject } from './run-gut.mjs';

const EXAMPLE = path.join(GODOT_DIR, '..', 'schema', 'examples', 'claude-code-transcript.jsonl');
const EXPECTED = JSON.parse(readFileSync(path.join(GODOT_DIR, 'test', 'fixtures', 'expected-trace.json'), 'utf8'))['claude-code-fixture'];

let godot;
const running = [];

before(() => {
  godot = resolveGodot();
  ensureBridgeBuilt();
  importProject(godot);
});

after(() => {
  for (const child of running) child.kill();
});

/** The visits that the client printed, by actor: { 'agent 1': [labels], 'helper 1': [labels] }. */
export function visits(lines) {
  const out = {};
  for (const line of lines) {
    const match = /^\[trace\] (agent \d+|helper \d+): (.*)$/.exec(line);
    if (match) (out[match[1]] ??= []).push(match[2]);
  }
  return out;
}

/** Runs the client headless against the bridge on `port`. */
function startClient(port) {
  const child = spawn(godot, ['--headless', '--path', GODOT_DIR, '--', `--bridge=ws://127.0.0.1:${port}/ws`, '--trace', '--log-events'], { stdio: ['ignore', 'pipe', 'pipe'] });
  running.push(child);
  const lines = [];
  let rest = '';
  child.stdout.on('data', (chunk) => {
    rest += chunk.toString('utf8');
    const parts = rest.split(/\r?\n/);
    rest = parts.pop();
    lines.push(...parts);
  });
  child.stderr.on('data', (chunk) => lines.push(`stderr: ${chunk.toString('utf8').trim()}`));
  return { child, lines };
}

async function waitFor(predicate, what, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const found = await predicate();
    if (found) return found;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`timed out waiting for ${what}`);
}

/** Runs `agent-workshop-bridge replay` (the replay command of the bridge) against the bridge. */
function replay(port, speed) {
  return new Promise((resolve, reject) => {
    const child = spawn(bridgeBinary(), ['replay', EXAMPLE, '--speed', String(speed), '--url', `http://127.0.0.1:${port}`], {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    });
    let out = '';
    child.stdout.on('data', (chunk) => { out += chunk; });
    child.stderr.on('data', (chunk) => { out += chunk; });
    child.on('error', reject);
    child.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`replay exited with ${code}: ${out}`))));
  });
}

async function run(speed, waitSeconds) {
  const bridge = await startBridge();
  const port = bridge.port;
  const client = startClient(port);
  try {
    await waitFor(async () => (await (await fetch(`http://127.0.0.1:${port}/health`)).json()).clients >= 1, 'the client to connect', 30000);
    const out = await replay(port, speed);
    assert.match(out, /17 events|events from/);
    await waitFor(() => (visits(client.lines)['agent 1'] ?? []).includes('celebration'), 'the penguin to celebrate', waitSeconds * 1000);
    // the helper goes to its station a moment after the penguin starts to celebrate: leave a little time
    await new Promise((resolve) => setTimeout(resolve, 600));
    return { lines: client.lines, visits: visits(client.lines) };
  } finally {
    client.child.kill();
    await bridge.stop();
  }
}

test('a session replayed at once (--speed 0) plays, and the penguin visits the stations in the order of the real Claude Code trace', async () => {
  const result = await run(0, 60);
  assert.deepEqual(result.visits['agent 1'], EXPECTED.trace['agent 1']);
  assert.ok(Object.keys(result.visits).every((who) => who === 'agent 1' || who === 'helper 1'), 'one penguin and its helper at most');
  assert.ok(result.lines.some((line) => line.startsWith('[live] event ')), 'the events reached the client');
});

test('a session replayed at a speed of 4 plays the same way', async () => {
  const result = await run(4, 90);
  assert.deepEqual(result.visits['agent 1'], EXPECTED.trace['agent 1']);
});
