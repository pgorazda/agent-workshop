#!/usr/bin/env node
// Starts a bridge binary and checks that it works. The release workflow runs it on every platform that it builds for.
//
//   node bridge/tools/smoke.mjs <path to agent-workshop-bridge>
//
// It checks `--version`, starts `serve --port 0`, reads `GET /health`, posts one event and reads it from a WebSocket
// client. It needs Node 22 or later (global WebSocket). Exit code 1 means that something failed.

import { spawnSync } from 'node:child_process';
import { startBridge } from './bridge-binary.mjs';

const binary = process.argv[2];
if (!binary) {
  console.error('Usage: node bridge/tools/smoke.mjs <path to agent-workshop-bridge>');
  process.exit(2);
}

const version = spawnSync(binary, ['--version'], { encoding: 'utf8' });
if (version.status !== 0 || !/^agent-workshop-bridge \d+\.\d+\.\d+/.test(version.stdout)) {
  console.error(`--version failed (exit code ${version.status}): ${version.stdout}${version.stderr}`);
  process.exit(1);
}
console.log(version.stdout.trim());

const bridge = await startBridge({ env: { ...process.env, ARENA_BRIDGE_BIN: binary } });
try {
  const health = await (await fetch(`http://127.0.0.1:${bridge.port}/health`)).json();
  if (health.ok !== true || health.schema !== 1) throw new Error(`unexpected health answer: ${JSON.stringify(health)}`);

  const socket = new WebSocket(`ws://127.0.0.1:${bridge.port}/ws`);
  const messages = [];
  socket.onmessage = (message) => messages.push(JSON.parse(message.data));
  await new Promise((resolve, reject) => ((socket.onopen = resolve), (socket.onerror = () => reject(new Error('the WebSocket did not open')))));
  const event = { v: 1, framework: 'smoke', session: 's', type: 'thinking' };
  const res = await fetch(`http://127.0.0.1:${bridge.port}/event`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(event) });
  if (res.status !== 202) throw new Error(`POST /event answered ${res.status}`);
  const start = Date.now();
  while (messages.length < 2 && Date.now() - start < 5000) await new Promise((r) => setTimeout(r, 20));
  socket.close();
  if (messages[0]?.type !== 'hello' || messages[1]?.type !== 'thinking') throw new Error(`unexpected messages: ${JSON.stringify(messages)}`);
  console.log(`The bridge works on port ${bridge.port}: health, hello and one event.`);
} catch (err) {
  console.error(`smoke test failed: ${err.message}`);
  process.exitCode = 1;
} finally {
  await bridge.stop();
}
