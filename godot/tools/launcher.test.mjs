// The bridge launcher of the Godot app (ADR 0014, phase R-8 of docs/rust-bridge-plan.md).
//
//   node --test        (from godot/; set GODOT, see README.md)
//
// The tests run the real launcher headless (tools/launcher_probe.gd) and the real bridge binary, and check what the rules say:
// the app starts the bridge only when asked, only for a local address, only when none runs; it stops its own bridge when it quits,
// also when it is killed; and it never stops a bridge that it did not start.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { bridgeBinary, ensureBridgeBuilt, startBridge } from '../../bridge/tools/bridge-binary.mjs';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';
import { importProject } from './run-gut.mjs';

let godot;
let binary;
const running = new Set();

before(() => {
  godot = resolveGodot();
  binary = ensureBridgeBuilt() && bridgeBinary();
  importProject(godot);
});

after(() => {
  for (const child of running) child.kill();
});

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

/** Runs the probe headless with the given arguments. Returns { child, lines, waitFor, exited }. */
function startProbe(args, { script = 'res://tools/launcher_probe.gd' } = {}) {
  const child = spawn(godot, ['--headless', '--path', GODOT_DIR, '-s', script, '--', ...args], { stdio: ['ignore', 'pipe', 'pipe'] });
  running.add(child);
  const lines = [];
  let rest = '';
  child.stdout.on('data', (chunk) => {
    rest += chunk.toString('utf8');
    const parts = rest.split(/\r?\n/);
    rest = parts.pop();
    lines.push(...parts);
  });
  child.stderr.on('data', (chunk) => lines.push(`stderr: ${chunk.toString('utf8').trim()}`));
  const exited = new Promise((resolve) => child.on('exit', resolve));
  const waitFor = async (predicate, what, timeoutMs = 20000) => {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const found = predicate(lines);
      if (found) return found;
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    throw new Error(`timed out waiting for ${what}. Output so far:\n${lines.join('\n')}`);
  };
  return { child, lines, waitFor, exited };
}

const states = (lines) => lines.filter((l) => l.startsWith('STATE ')).map((l) => l.slice(6));
const notes = (lines) => lines.filter((l) => l.startsWith('NOTE ')).map((l) => l.slice(5));
const pidOf = (lines) => Number((lines.find((l) => l.startsWith('PID ')) ?? '').slice(4));

async function healthy(port) {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(500) });
    return res.status === 200 && (await res.json()).ok === true;
  } catch {
    return false;
  }
}

async function until(predicate, what, timeoutMs = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`timed out waiting for ${what}`);
}

const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

test('the app starts the bridge when none runs, the bridge works, and a normal quit stops it', async () => {
  const port = await freePort();
  const probe = startProbe([`--bridge=ws://127.0.0.1:${port}/ws`, `--start-bridge=${binary}`, '--probe-quit-after=4']);
  await probe.waitFor((lines) => states(lines).includes('running'), 'the bridge to run');
  assert.ok(await healthy(port), 'the bridge answers on the port of the address');
  assert.ok(pidOf(probe.lines) > 0, 'the launcher knows the process id');
  assert.deepEqual(notes(probe.lines), [], 'no note when all is well');
  await probe.exited;
  await until(async () => !(await healthy(port)), 'the bridge to stop after a normal quit');
});

test('the bridge ends when the app is killed (a crash)', async () => {
  const port = await freePort();
  const probe = startProbe([`--bridge=ws://127.0.0.1:${port}/ws`, `--start-bridge=${binary}`]);
  await probe.waitFor((lines) => states(lines).includes('running'), 'the bridge to run');
  const pid = pidOf(probe.lines);
  assert.ok(await healthy(port));
  probe.child.kill('SIGKILL');
  await probe.exited;
  await until(async () => !(await healthy(port)), 'the bridge to stop after a kill of the app');
  await until(async () => !alive(pid), 'the process of the bridge to be gone');
});

test('a bridge that already runs is used and is not stopped when the app quits', async () => {
  const bridge = await startBridge();
  try {
    const probe = startProbe([`--bridge=ws://127.0.0.1:${bridge.port}/ws`, `--start-bridge=${binary}`, '--probe-quit-after=2']);
    await probe.waitFor((lines) => states(lines).includes('using_existing'), 'the launcher to use the running bridge');
    assert.equal(pidOf(probe.lines) > 0, false, 'it started no program');
    await probe.exited;
    assert.ok(await healthy(bridge.port), 'the bridge that was there before is still there');
    assert.deepEqual(notes(probe.lines), []);
  } finally {
    await bridge.stop();
  }
});

test('a port held by another program gives one note and no loop', async () => {
  const holder = net.createServer((socket) => socket.on('error', () => {})); // accepts and says nothing
  await new Promise((resolve) => holder.listen(0, '127.0.0.1', resolve));
  const port = holder.address().port;
  try {
    const probe = startProbe([`--bridge=ws://127.0.0.1:${port}/ws`, `--start-bridge=${binary}`, '--probe-quit-after=5']);
    await probe.waitFor((lines) => states(lines).includes('failed'), 'the launcher to fail', 15000);
    const text = notes(probe.lines).join('\n').toLowerCase();
    assert.match(text, /^bridge: could not listen on 127\.0\.0\.1:\d+/, text);
    assert.match(text, /in use|only one usage/, text);
    await probe.exited;
    assert.equal(notes(probe.lines).length, 1, 'one note, not one for each try');
  } finally {
    holder.close();
  }
});

test('an address that is not on this computer starts nothing', async () => {
  for (const url of ['ws://example.test:8787/ws', 'ws://192.168.1.5:8787/ws', 'wss://127.0.0.1:8787/ws']) {
    const probe = startProbe([`--bridge=${url}`, `--start-bridge=${binary}`, '--probe-quit-after=1']);
    await probe.waitFor((lines) => states(lines).includes('failed'), `the launcher to refuse ${url}`);
    assert.match(notes(probe.lines)[0], /not on this computer/);
    assert.equal(pidOf(probe.lines) > 0, false);
    await probe.exited;
  }
});

test('a configured path that is not a file gives a note and starts nothing', async () => {
  const port = await freePort();
  const probe = startProbe([`--bridge=ws://127.0.0.1:${port}/ws`, '--start-bridge=/nonexistent/agent-workshop-bridge', '--probe-quit-after=2']);
  await probe.waitFor((lines) => states(lines).includes('failed'), 'the launcher to fail');
  assert.match(notes(probe.lines)[0], /^Bridge program not found: \/nonexistent\/agent-workshop-bridge/);
  assert.equal(await healthy(port), false);
  await probe.exited;
});

test('the app itself starts the bridge with the option, and shows its events', async () => {
  // The real app (live view), headless: it starts the bridge, connects, and prints an event that is posted to the bridge.
  const port = await freePort();
  const app = spawn(godot, ['--headless', '--path', GODOT_DIR, '--', `--bridge=ws://127.0.0.1:${port}/ws`, `--start-bridge=${binary}`, '--log-events'], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  running.add(app);
  const lines = [];
  let rest = '';
  app.stdout.on('data', (chunk) => {
    rest += chunk.toString('utf8');
    const parts = rest.split(/\r?\n/);
    rest = parts.pop();
    lines.push(...parts);
  });
  try {
    await until(() => healthy(port), 'the app to start the bridge', 20000);
    await until(async () => (await (await fetch(`http://127.0.0.1:${port}/health`)).json()).clients >= 1, 'the app to connect to its bridge', 20000);
    const res = await fetch(`http://127.0.0.1:${port}/event`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ v: 1, framework: 'launcher-test', session: 's1', type: 'tool_start', tool: 'Read', category: 'read', target: 'a.txt', id: 't1' }),
    });
    assert.equal(res.status, 202);
    await until(() => lines.some((l) => l.startsWith('[live] event ')), 'the app to show the event');
  } finally {
    app.kill('SIGKILL');
    await new Promise((resolve) => app.on('exit', resolve));
  }
  await until(async () => !(await healthy(port)), 'the bridge to stop after the app was killed');
});

test('without the option the app starts no bridge', async () => {
  const port = await freePort();
  const app = spawn(godot, ['--headless', '--path', GODOT_DIR, '--', `--bridge=ws://127.0.0.1:${port}/ws`, '--no-start-bridge', '--log-events'], { stdio: 'ignore' });
  running.add(app);
  try {
    await new Promise((resolve) => setTimeout(resolve, 4000));
    assert.equal(await healthy(port), false);
  } finally {
    app.kill('SIGKILL');
    await new Promise((resolve) => app.on('exit', resolve));
  }
});
