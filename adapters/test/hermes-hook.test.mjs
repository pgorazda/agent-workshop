// The Hermes hook script (adapters/hermes/arena-hook.sh) forwards its standard input to the real
// bridge, and stays silent with exit code 0 when the bridge is down.
//
//   node --test 'adapters/test/*.test.mjs'        (Node 22 or later; needs sh and curl, or the test is skipped)

import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { ensureBridgeBuilt, openClient, startBridge, summarize } from './helpers.mjs';

before(() => ensureBridgeBuilt());

test('arena-hook.sh forwards stdin to the bridge, and stays silent with exit 0 when the bridge is down', async (t) => {
  const script = fileURLToPath(new URL('../hermes/arena-hook.sh', import.meta.url));
  // Windows has no executable bit and cannot run a .sh file directly, so it starts the script with bash.
  const windows = process.platform === 'win32';
  if (!windows) assert.ok((await stat(script)).mode & 0o100, 'the script is executable');
  const run = (url, input) =>
    new Promise((resolve, reject) => {
      const [command, args] = windows ? ['bash', [script.replaceAll('\\', '/')]] : [script, []];
      const child = spawn(command, args, { env: { ...process.env, ARENA_BRIDGE_HTTP: url }, stdio: ['pipe', 'pipe', 'pipe'] });
      let out = '';
      child.stdout.on('data', (d) => (out += d));
      child.stderr.on('data', (d) => (out += d));
      child.on('error', reject);
      child.on('close', (code) => resolve({ code, out }));
      child.stdin.end(input);
    });

  const bridge = await startBridge();
  const client = await openClient(bridge.port);
  const payload = JSON.stringify({
    hook_event_name: 'pre_tool_call',
    tool_name: 'terminal',
    tool_input: { command: 'make test' },
    session_id: 's1',
    extra: { tool_call_id: 'c1' },
  });
  try {
    const ok = await run(`http://127.0.0.1:${bridge.port}/`, payload); // a trailing slash is tolerated
    assert.deepEqual(ok, { code: 0, out: '' });
    await client.waitFor(1);
    assert.equal(summarize(client.events[0]), 'tool_start:exec:make test');
    const offline = await run('http://127.0.0.1:1', payload);
    assert.deepEqual(offline, { code: 0, out: '' });
  } catch (err) {
    if (err?.code === 'ENOENT') return t.skip('curl or sh is not available');
    throw err;
  } finally {
    client.close();
    await bridge.stop();
  }
});
