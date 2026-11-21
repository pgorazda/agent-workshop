// OpenCode plugin: forwards the events Agent Workshop needs to the bridge.
//
// Install: copy this file to .opencode/plugins/arena.js in your project (or to
// ~/.config/opencode/plugins/arena.js for all projects). OpenCode loads it at startup.
//
// Only the few fields the bridge needs are sent: no message text, tool output, diffs or file
// contents. Posting is queued so events keep their order, never awaited by OpenCode, and fails
// open. The bridge maps the events (bridge/src/adapters/opencode.rs).
//
// Keep this file to a single export: OpenCode treats exports of a plugin file as plugins.

const BRIDGE = (process.env.ARENA_BRIDGE_HTTP ?? 'http://127.0.0.1:8787').replace(/\/$/, '');

// Tool arguments that say what a call acts on.
const INPUT_KEYS = ['file_path', 'filePath', 'notebook_path', 'command', 'pattern', 'url', 'query', 'description', 'path'];

function slimInput(input) {
  if (input === null || typeof input !== 'object') return undefined;
  const out = {};
  for (const key of INPUT_KEYS) {
    if (typeof input[key] === 'string') out[key] = input[key].slice(0, 300);
  }
  return out;
}

const slimInfo = (info) => ({ id: info?.id, parentID: info?.parentID });

// Returns the reduced event to forward, or undefined when Agent Workshop does not need it.
function slim(event) {
  const props = event?.properties ?? {};
  switch (event?.type) {
    case 'session.created':
    case 'session.updated':
    case 'session.deleted':
      return { type: event.type, properties: { info: slimInfo(props.info) } };
    case 'session.idle':
      return { type: event.type, properties: { sessionID: props.sessionID } };
    case 'session.error':
      return { type: event.type, properties: { sessionID: props.sessionID, error: { name: props.error?.name } } };
    case 'session.status':
      return {
        type: event.type,
        properties: { sessionID: props.sessionID, status: { type: props.status?.type, attempt: props.status?.attempt } },
      };
    case 'permission.updated':
    case 'permission.asked':
      return { type: event.type, properties: { sessionID: props.sessionID, title: props.title } };
    case 'message.updated':
      if (props.info?.role !== 'user') return undefined;
      return { type: event.type, properties: { info: { id: props.info.id, sessionID: props.info.sessionID, role: 'user' } } };
    case 'message.part.updated': {
      const part = props.part;
      if (part?.type === 'tool') {
        return {
          type: event.type,
          properties: {
            part: {
              type: 'tool',
              id: part.id,
              sessionID: part.sessionID,
              callID: part.callID,
              tool: part.tool,
              state: {
                status: part.state?.status,
                input: slimInput(part.state?.input),
                error: typeof part.state?.error === 'string' ? part.state.error.slice(0, 300) : undefined,
              },
            },
          },
        };
      }
      // Text parts stream token by token and are not needed. Reasoning parts only signal "thinking".
      if (part?.type === 'reasoning') {
        return {
          type: event.type,
          properties: { part: { type: 'reasoning', id: part.id, sessionID: part.sessionID, time: { end: part.time?.end } } },
        };
      }
      return undefined;
    }
    default:
      return undefined;
  }
}

let queue = Promise.resolve();

function post(event) {
  queue = queue.then(async () => {
    try {
      await fetch(`${BRIDGE}/hook/opencode`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ event }),
        signal: AbortSignal.timeout(1000),
      });
    } catch {
      // Bridge not running: ignore.
    }
  });
}

export const ArenaPlugin = async () => ({
  event: async ({ event }) => {
    const reduced = slim(event);
    if (reduced) post(reduced);
  },
});
