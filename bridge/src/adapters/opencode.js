// OpenCode adapter (https://opencode.ai). Input is the `Event` objects OpenCode passes to a
// plugin's `event` hook (types: @opencode-ai/sdk), wrapped as { event } by the plugin.
//
// Events used:
//   session.created / session.updated   Session { id, parentID? }: a parentID marks a subagent
//   session.idle                         root: done; subagent: subagent_end
//   session.deleted, session.error, session.status (retry)
//   message.updated                      role "user" means the agent starts thinking
//   message.part.updated                 ToolPart { callID, tool, state } and ReasoningPart
//   permission.updated                   waiting_permission
//
// Tool lifecycle comes from ToolPart.state.status (pending, running, completed, error), which
// reports failures reliably, unlike the tool.execute.after hook.
//
// Subagents run in child sessions. Their events are reported under the root session with
// agent = the child session id, which is also the id of the subagent_start event, so the game
// can attach the activity to the helper penguin.

import { categoryFor } from '../categories.js';
import { describeTarget } from '../targets.js';
import { SCHEMA_VERSION } from '../schema.js';

const FRAMEWORK = 'opencode';
const MAX_REMEMBERED = 5000;

function remember(set, value) {
  if (set.size >= MAX_REMEMBERED) set.clear();
  set.add(value);
}

export function createOpenCodeAdapter() {
  // sessionID -> { root, agent, parent: { sessionID, agent } | undefined }
  const sessions = new Map();
  const startedTools = new Set();
  const endedTools = new Set();
  const thinkingParts = new Set();
  const userMessages = new Set();
  const openSubagents = new Set();

  function contextFor(sessionID) {
    let ctx = sessions.get(sessionID);
    if (!ctx) {
      ctx = { root: sessionID, agent: 'main', parent: undefined };
      sessions.set(sessionID, ctx);
    }
    return ctx;
  }

  const make = (sessionID, type, extra = {}) => {
    const ctx = contextFor(sessionID);
    return { v: SCHEMA_VERSION, framework: FRAMEWORK, session: ctx.root, agent: ctx.agent, type, ...extra };
  };

  // Registers a session the first time it is seen. A child session also announces a subagent.
  function register(info) {
    if (!info || typeof info.id !== 'string' || sessions.has(info.id)) return [];
    if (info.parentID) {
      const parent = contextFor(info.parentID);
      sessions.set(info.id, {
        root: parent.root,
        agent: info.id,
        parent: { sessionID: info.parentID, agent: parent.agent },
      });
      remember(openSubagents, info.id);
      return [make(info.parentID, 'subagent_start', { id: info.id })];
    }
    sessions.set(info.id, { root: info.id, agent: 'main', parent: undefined });
    return [make(info.id, 'session_start')];
  }

  function endSubagent(sessionID) {
    const ctx = sessions.get(sessionID);
    if (!ctx?.parent || !openSubagents.delete(sessionID)) return [];
    return [make(ctx.parent.sessionID, 'subagent_end', { id: sessionID })];
  }

  function fromToolPart(part) {
    const sessionID = part.sessionID;
    const key = part.callID ?? part.id;
    const status = part.state?.status;
    if (!sessionID || !key || !part.tool) return [];
    const events = [];

    const start = () => {
      if (startedTools.has(key)) return;
      remember(startedTools, key);
      events.push(
        make(sessionID, 'tool_start', {
          id: key,
          tool: part.tool,
          category: categoryFor(FRAMEWORK, part.tool),
          target: describeTarget(part.state?.input),
        }),
      );
    };

    if (status === 'running') {
      start(); // 'pending' is skipped: its input is usually still empty
    } else if (status === 'completed' || status === 'error') {
      if (endedTools.has(key)) return [];
      start();
      remember(endedTools, key);
      events.push(
        make(sessionID, 'tool_end', {
          id: key,
          tool: part.tool,
          ok: status === 'completed',
          error: status === 'error' && typeof part.state.error === 'string' ? part.state.error : undefined,
        }),
      );
    }
    return events;
  }

  function fromEvent(event) {
    if (event === null || typeof event !== 'object') return [];
    const props = event.properties ?? {};

    switch (event.type) {
      case 'session.created':
      case 'session.updated':
        return register(props.info);

      case 'session.idle': {
        const ctx = sessions.get(props.sessionID);
        if (!props.sessionID) return [];
        return ctx?.parent ? endSubagent(props.sessionID) : [make(props.sessionID, 'done')];
      }

      case 'session.deleted': {
        const events = props.info?.id ? endSubagent(props.info.id) : [];
        if (props.info?.id) sessions.delete(props.info.id);
        return events;
      }

      case 'session.error':
        if (!props.sessionID) return [];
        return [make(props.sessionID, 'error', { message: props.error?.name })];

      case 'session.status':
        if (props.status?.type !== 'retry' || !props.sessionID) return [];
        return [make(props.sessionID, 'error', { message: `retry ${props.status.attempt}` })];

      case 'message.updated': {
        const info = props.info;
        if (info?.role !== 'user' || !info.id || !info.sessionID || userMessages.has(info.id)) return [];
        remember(userMessages, info.id);
        return [make(info.sessionID, 'thinking')];
      }

      case 'message.part.updated': {
        const part = props.part;
        if (!part) return [];
        if (part.type === 'tool') return fromToolPart(part);
        if (part.type === 'reasoning' && part.sessionID && part.id && !thinkingParts.has(part.id) && !part.time?.end) {
          remember(thinkingParts, part.id);
          return [make(part.sessionID, 'thinking')];
        }
        return [];
      }

      case 'permission.updated':
      case 'permission.asked':
        if (!props.sessionID) return [];
        return [make(props.sessionID, 'waiting_permission', { message: props.title })];

      default:
        return [];
    }
  }

  return {
    /** Payload accepted by POST /hook/opencode: { event } or a bare event. */
    fromPayload(payload) {
      if (payload === null || typeof payload !== 'object') return [];
      return fromEvent(payload.event ?? payload);
    },
    fromEvent,
  };
}
