// Hermes Agent adapter (https://github.com/NousResearch/hermes-agent, package hermes-agent).
//
// Input is the JSON that Hermes pipes to a configured shell hook (agent/shell_hooks.py):
//
//   { hook_event_name, tool_name, tool_input, session_id, cwd, extra }
//
// `extra` holds every other hook kwarg. Events used:
//
//   on_session_start          session_start
//   pre_api_request           thinking, only for the first API call of a turn (extra.api_call_count === 1)
//   pre_tool_call             tool_start   (tool_input = args, extra.tool_call_id)
//   post_tool_call            tool_end     (extra.status "ok" | "error" | "blocked", extra.error_message)
//   pre_approval_request      waiting_permission
//   subagent_start / _stop    helper penguin (extra.child_session_id; session_id is the parent session)
//   on_session_end            done, or error when extra.completed === false
//   api_request_error         error
//
// `pre_llm_call` is deliberately not used: its payload carries the whole conversation history.
//
// Notes:
// - Approval events carry no session_id, so they are attributed to the session seen most recently.
// - A subagent's own tool calls arrive with the child session id. They are reported under the
//   parent's session with agent = the child session id, which is also the id of the
//   subagent_start event, so the game attaches them to the helper penguin.

import { categoryFor } from '../categories.js';
import { describeTarget } from '../targets.js';
import { SCHEMA_VERSION } from '../schema.js';

const FRAMEWORK = 'hermes';

export function createHermesAdapter() {
  // sessionId -> { root, agent, parent: { session, agent } | undefined }
  const sessions = new Map();
  let lastSession;

  function contextFor(sessionId) {
    let ctx = sessions.get(sessionId);
    if (!ctx) {
      ctx = { root: sessionId, agent: 'main', parent: undefined };
      sessions.set(sessionId, ctx);
    }
    return ctx;
  }

  const make = (ctx, type, extra = {}) => ({
    v: SCHEMA_VERSION,
    framework: FRAMEWORK,
    session: ctx.root,
    agent: ctx.agent,
    type,
    ...extra,
  });

  const asString = (x) => (typeof x === 'string' && x.length > 0 ? x : undefined);

  function fromHook(payload) {
    if (payload === null || typeof payload !== 'object') return [];
    const name = payload.hook_event_name;
    const extra = payload.extra !== null && typeof payload.extra === 'object' ? payload.extra : {};

    // Subagent hooks: session_id is the parent session.
    if (name === 'subagent_start' || name === 'subagent_stop') {
      const parentId = asString(payload.session_id) ?? lastSession;
      const childId = asString(extra.child_session_id) ?? asString(extra.child_subagent_id);
      if (!parentId || !childId) return [];
      const parent = contextFor(parentId);
      if (name === 'subagent_start') {
        sessions.set(childId, { root: parent.root, agent: childId, parent: { session: parent.root, agent: parent.agent } });
        return [make(parent, 'subagent_start', { id: childId })];
      }
      const known = sessions.get(childId);
      sessions.delete(childId);
      return [make(known?.parent ? { root: known.parent.session, agent: known.parent.agent } : parent, 'subagent_end', { id: childId })];
    }

    const sessionId = asString(payload.session_id) ?? lastSession ?? asString(extra.session_key) ?? 'hermes';
    if (asString(payload.session_id)) lastSession = payload.session_id;
    const ctx = contextFor(sessionId);

    switch (name) {
      case 'on_session_start':
        return ctx.agent === 'main' ? [make(ctx, 'session_start')] : [];

      case 'pre_api_request':
        return extra.api_call_count === 1 ? [make(ctx, 'thinking')] : [];

      case 'pre_tool_call': {
        const tool = asString(payload.tool_name);
        if (!tool) return [];
        return [
          make(ctx, 'tool_start', {
            id: asString(extra.tool_call_id),
            tool,
            category: categoryFor(FRAMEWORK, tool),
            target: describeTarget(payload.tool_input),
          }),
        ];
      }

      case 'post_tool_call': {
        const tool = asString(payload.tool_name);
        if (!tool) return [];
        const status = extra.status;
        const ok = status === undefined ? !extra.error_type : status === 'ok';
        return [
          make(ctx, 'tool_end', {
            id: asString(extra.tool_call_id),
            tool,
            ok,
            error: ok ? undefined : (asString(extra.error_message) ?? (status === 'blocked' ? 'blocked' : undefined)),
          }),
        ];
      }

      case 'pre_approval_request':
        return [make(ctx, 'waiting_permission', { message: asString(extra.description) })];

      case 'on_session_end':
        if (ctx.agent !== 'main') return []; // a subagent ends with subagent_stop
        return extra.completed === false
          ? [make(ctx, 'error', { message: extra.interrupted ? 'interrupted' : 'incomplete' })]
          : [make(ctx, 'done')];

      case 'api_request_error':
        return [make(ctx, 'error', { message: asString(extra.error_type) })];

      default:
        return [];
    }
  }

  return { fromHook };
}
