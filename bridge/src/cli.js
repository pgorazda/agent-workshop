#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { createBridge } from './server.js';
import { transcriptToEvents } from './adapters/claude-code.js';

const USAGE = `Usage:
  node src/cli.js serve [--port 8787] [--host 127.0.0.1] [--redact-targets]
  node src/cli.js replay <transcript.jsonl> [--speed 4] [--max-gap 1500] [--url http://127.0.0.1:8787]
  pi --mode json "prompt" | node src/cli.js ingest pi [--tee] [--url http://127.0.0.1:8787]

serve    run the bridge (HTTP in, WebSocket out)
replay   post a recorded Claude Code transcript to a running bridge, preserving timing
         --speed N     playback speed multiplier (0 = no delays)
         --max-gap MS  longest pause kept between two events, before the speed factor
ingest   read a framework's JSON event stream from stdin and forward it to a running bridge
         (only "pi" for now). --tee also copies each line to stdout.`;

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const name = arg.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) flags[name] = true;
      else {
        flags[name] = next;
        i += 1;
      }
    } else positional.push(arg);
  }
  return { positional, flags };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function serve(flags) {
  const bridge = createBridge({
    host: flags.host ?? process.env.ARENA_HOST ?? '127.0.0.1',
    port: Number(flags.port ?? process.env.ARENA_PORT ?? 8787),
    redactTargets: Boolean(flags['redact-targets']) || process.env.ARENA_REDACT_TARGETS === '1',
    log: (line) => console.log(`[bridge] ${line}`),
  });
  const addr = await bridge.listen();
  console.log(`[bridge] listening on http://${addr.address}:${addr.port} (ws path /ws)`);
}

async function replay(file, flags) {
  if (!file) throw new Error('replay needs a transcript file');
  const url = String(flags.url ?? 'http://127.0.0.1:8787').replace(/\/$/, '');
  const speed = Number(flags.speed ?? 4);
  const maxGap = Number(flags['max-gap'] ?? 1500);
  const events = transcriptToEvents(await readFile(file, 'utf8'));
  console.log(`[replay] ${events.length} events from ${file} at speed ${speed}`);

  let previous;
  for (const event of events) {
    if (speed > 0 && previous !== undefined && event.ts !== undefined) {
      const gap = Math.min(Math.max(event.ts - previous, 0), maxGap);
      await sleep(gap / speed);
    }
    previous = event.ts ?? previous;
    // Replay stamps events with the current time so clients see them as live.
    const live = { ...event, ts: Date.now() };
    const res = await fetch(`${url}/event`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(live),
    });
    if (!res.ok) throw new Error(`bridge rejected an event (${res.status}): ${await res.text()}`);
  }
  console.log('[replay] done');
}

async function ingestPi(flags) {
  const url = String(flags.url ?? process.env.ARENA_BRIDGE_HTTP ?? 'http://127.0.0.1:8787').replace(/\/$/, '');
  let session = `pi-${Date.now()}`;
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of rl) {
    if (flags.tee) console.log(line);
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue; // not JSON: ignore, the stream may contain other output
    }
    if (event?.type === 'session' && typeof event.id === 'string') session = event.id;
    try {
      await fetch(`${url}/hook/pi`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ session, event }),
        signal: AbortSignal.timeout(1000),
      });
    } catch {
      // Fail open: a missing bridge must never break the agent's output.
    }
  }
}

const { positional, flags } = parseArgs(process.argv.slice(2));
const [command, ...rest] = positional;

try {
  if (command === 'serve') await serve(flags);
  else if (command === 'replay') await replay(rest[0], flags);
  else if (command === 'ingest' && rest[0] === 'pi') await ingestPi(flags);
  else {
    console.log(USAGE);
    process.exitCode = command ? 1 : 0;
  }
} catch (err) {
  console.error(`error: ${err.message}`);
  process.exitCode = 1;
}
