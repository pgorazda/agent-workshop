// The link between the bridge and the Godot client (phase G-0, spikes S-1).
//
//   node --test        (from godot/; set GODOT, see README.md)
//
// The test starts the real bridge on a free port, runs the real client headless (tools/link_probe.gd),
// posts events and reads what the client printed.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { createBridge } from '../../bridge/src/server.js';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';
import { importProject } from './run-gut.mjs';

let godot;
const running = [];

before(() => {
  godot = resolveGodot();
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

/** Runs the client headless against `port`. Returns the lines it printed and a way to wait for one. */
function startProbe(port) {
  const child = spawn(godot, ['--headless', '--path', GODOT_DIR, '-s', 'res://tools/link_probe.gd', '--', `--bridge=ws://127.0.0.1:${port}/ws`], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
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

  const waitFor = async (predicate, what, timeoutMs = 15000) => {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const found = predicate(lines);
      if (found) return found;
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    throw new Error(`timed out waiting for ${what}. Output so far:\n${lines.join('\n')}`);
  };
  return { child, lines, waitFor };
}

const ids = (lines) => lines.filter((l) => l.startsWith('EVENT ')).map((l) => l.split(' ')[1]);
const states = (lines) => lines.filter((l) => l.startsWith('STATE ')).map((l) => l.slice(6));
const tries = (lines) => Math.max(0, ...lines.filter((l) => l.startsWith('TRY ')).map((l) => Number(l.split(' ')[1])));
const count = (lines, state) => states(lines).filter((s) => s === state).length;

const makeEvents = (from, to) =>
  Array.from({ length: to - from }, (_, i) => ({
    v: 1,
    framework: 'link-test',
    session: 's1',
    agent: 'main',
    type: 'tool_start',
    tool: 'T',
    category: 'read',
    id: `n-${from + i}`,
  }));

async function post(port, events) {
  const res = await fetch(`http://127.0.0.1:${port}/event`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(events),
  });
  assert.equal(res.status, 202, await res.text());
}

const expectedIds = (from, to) => makeEvents(from, to).map((e) => e.id);

test('the client gets events in order, ignores hello, and reconnects after the bridge restarts', async () => {
  const port = await freePort();
  let bridge = createBridge({ port });
  await bridge.listen();
  const probe = startProbe(port);

  await probe.waitFor((lines) => states(lines).includes('open'), 'the client to connect');
  assert.deepEqual(ids(probe.lines), [], 'the hello message is not listed as an event');

  // A few single events, then a burst of 200 in one post (the client reads at most 64 in a frame).
  for (const event of makeEvents(0, 5)) await post(port, [event]);
  await post(port, makeEvents(5, 205));
  await probe.waitFor((lines) => ids(lines).length >= 205, 'the first 205 events');
  assert.deepEqual(ids(probe.lines), expectedIds(0, 205), 'events arrive in order, none lost, none doubled');

  const max = Math.max(0, ...probe.lines.filter((l) => l.startsWith('MAXFRAME ')).map((l) => Number(l.split(' ')[1])));
  assert.ok(max <= 64, `at most 64 events in a frame (saw ${max})`);

  // Restart the bridge on the same port. The client must see the close and connect again.
  const opensBefore = count(probe.lines, 'open');
  await bridge.close();
  await probe.waitFor((lines) => count(lines, 'waiting') >= 1, 'the client to notice that the bridge is gone');
  bridge = createBridge({ port });
  await bridge.listen();
  const restarted = Date.now();
  await probe.waitFor((lines) => count(lines, 'open') > opensBefore, 'the client to reconnect', 10000);
  assert.ok(Date.now() - restarted < 6000, 'the client reconnects within a few seconds');

  await post(port, makeEvents(205, 210));
  await probe.waitFor((lines) => ids(lines).length >= 210, 'the events after the restart');
  assert.deepEqual(ids(probe.lines), expectedIds(0, 210), 'the stream goes on in order after the restart');

  probe.child.kill();
  await bridge.close();
});

test('the client keeps trying when no bridge runs, and connects when one starts', async () => {
  const port = await freePort();
  const probe = startProbe(port);
  // The first try fails or times out. On Windows a closed port takes about 30 s to fail, so the client
  // drops a try after 4 s. The client must start a second and a third try without help.
  await probe.waitFor((lines) => tries(lines) >= 3, 'three connection tries', 15000);

  const bridge = createBridge({ port });
  await bridge.listen();
  await probe.waitFor((lines) => states(lines).includes('open'), 'the client to connect to the late bridge', 10000);
  await post(port, makeEvents(0, 3));
  await probe.waitFor((lines) => ids(lines).length >= 3, 'events from the late bridge');
  assert.deepEqual(ids(probe.lines), expectedIds(0, 3));

  probe.child.kill();
  await bridge.close();
});

test('the client sends no Origin header (spike S-1)', async () => {
  // A native WebSocket client has no page, so it has no origin. The origin checks that are planned for
  // the bridge must let such a client in. This test fails when a Godot update starts to send one.
  const port = await freePort();
  const seen = new Promise((resolve) => {
    const server = http.createServer();
    server.on('upgrade', (req, socket) => {
      resolve(req.headers);
      socket.destroy();
      server.close();
    });
    server.listen(port, '127.0.0.1');
  });
  const probe = startProbe(port);
  const headers = await Promise.race([seen, new Promise((_, reject) => setTimeout(() => reject(new Error('no connection')), 15000))]);
  assert.equal(headers.upgrade, 'websocket');
  assert.equal(headers.origin, undefined, `unexpected Origin header: ${headers.origin}`);
  probe.child.kill();
});
