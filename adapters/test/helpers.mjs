// Helpers for the tests of the adapters' scripts (the OpenCode plugin, the Pi extension and the Hermes hook).
// They run the real bridge binary and read what a WebSocket client receives. They need Node 22 or later (global WebSocket).

import { ensureBridgeBuilt, startBridge } from '../../bridge/tools/bridge-binary.mjs';

export { ensureBridgeBuilt, startBridge };

/** One-line description of an event, used to compare streams in tests. */
export function summarize(e) {
  if (e.type === 'tool_start') return `tool_start:${e.category}:${e.target ?? ''}`;
  if (e.type === 'tool_end') return e.ok === false ? 'tool_end(fail)' : 'tool_end';
  return e.type;
}

/** A WebSocket client of the bridge. `events` holds what arrived after the hello message. */
export async function openClient(port) {
  const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const events = [];
  let hello = false;
  socket.onmessage = (message) => {
    const parsed = JSON.parse(message.data);
    if (!hello && parsed.type === 'hello') hello = true;
    else events.push(parsed);
  };
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = () => reject(new Error('the WebSocket did not open'));
  });
  const start = Date.now();
  while (!hello && Date.now() - start < 3000) await new Promise((r) => setTimeout(r, 10));
  if (!hello) throw new Error('no hello message');
  return {
    events,
    /** Waits until `count` events arrived. */
    async waitFor(count, ms = 5000) {
      const begin = Date.now();
      while (events.length < count && Date.now() - begin < ms) await new Promise((r) => setTimeout(r, 10));
      if (events.length < count) throw new Error(`only ${events.length} of ${count} events arrived: ${events.map(summarize).join(', ')}`);
      return events;
    },
    close: () => socket.close(),
  };
}
