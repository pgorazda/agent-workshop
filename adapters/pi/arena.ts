// Pi extension: forwards the events Agent Workshop needs to the bridge.
//
// Install: copy this file to ~/.pi/agent/extensions/arena.ts (or try it with `pi -e ./arena.ts`).
//
// Extensions see the same events as `pi --mode json`, so this works in interactive mode too.
// Only the few fields the bridge needs are sent: no message text, tool output or file contents.
// Posting is queued so events keep their order, never awaited by Pi, and fails open. The bridge
// maps the events (bridge/src/adapters/pi.js).

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const BRIDGE = (process.env.ARENA_BRIDGE_HTTP ?? "http://127.0.0.1:8787").replace(/\/$/, "");

// Tool arguments that say what a call acts on.
const ARG_KEYS = ["path", "file_path", "filePath", "command", "pattern", "url", "query", "description"];

function slimArgs(args: unknown): Record<string, string> | undefined {
  if (args === null || typeof args !== "object") return undefined;
  const source = args as Record<string, unknown>;
  const out: Record<string, string> = {};
  for (const key of ARG_KEYS) {
    const value = source[key];
    if (typeof value === "string") out[key] = value.slice(0, 300);
  }
  return out;
}

// Only used for the error text of a failed tool call.
function slimResult(result: unknown): { content: { type: "text"; text: string }[] } | undefined {
  const content = (result as { content?: unknown } | null)?.content;
  if (!Array.isArray(content)) return undefined;
  const first = content.find((c: { type?: string; text?: unknown }) => c?.type === "text" && typeof c.text === "string");
  return first ? { content: [{ type: "text", text: String(first.text).slice(0, 300) }] } : undefined;
}

let queue: Promise<void> = Promise.resolve();

function post(session: string, event: Record<string, unknown>): void {
  queue = queue.then(async () => {
    try {
      await fetch(`${BRIDGE}/hook/pi`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ session, event }),
        signal: AbortSignal.timeout(1000),
      });
    } catch {
      // Bridge not running: ignore.
    }
  });
}

function sessionId(ctx: { sessionManager: { getSessionId?: () => string } }): string {
  try {
    return ctx.sessionManager.getSessionId?.() ?? "pi";
  } catch {
    return "pi";
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => post(sessionId(ctx), { type: "session_start" }));
  pi.on("agent_start", async (_event, ctx) => post(sessionId(ctx), { type: "agent_start" }));
  pi.on("agent_end", async (_event, ctx) => post(sessionId(ctx), { type: "agent_end" }));

  pi.on("tool_execution_start", async (event, ctx) =>
    post(sessionId(ctx), {
      type: "tool_execution_start",
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      args: slimArgs(event.args),
    }),
  );

  pi.on("tool_execution_end", async (event, ctx) =>
    post(sessionId(ctx), {
      type: "tool_execution_end",
      toolCallId: event.toolCallId,
      toolName: event.toolName,
      isError: event.isError,
      result: event.isError ? slimResult(event.result) : undefined,
    }),
  );

  // message_update fires per token; only the start of a reasoning block matters.
  pi.on("message_update", async (event, ctx) => {
    if (event.assistantMessageEvent?.type === "thinking_start") {
      post(sessionId(ctx), { type: "message_update", assistantMessageEvent: { type: "thinking_start" } });
    }
  });
}
