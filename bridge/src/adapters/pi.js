// Pi adapter (https://github.com/badlogic/pi-mono, package @mariozechner/pi-coding-agent).
//
// Input is a Pi session event, either from `pi --mode json` (JSON lines on stdout) or from an
// extension's event handlers. Both use the same event shapes (AgentSessionEvent), so one mapper
// serves both:
//
//   session header            {"type":"session","id":"<uuid>",...}       (json mode only)
//   session_start             extension event
//   agent_start / agent_end   one per user prompt
//   message_update            assistantMessageEvent.type === "thinking_start" means reasoning began
//   tool_execution_start      { toolCallId, toolName, args }
//   tool_execution_end        { toolCallId, toolName, result, isError }
//   compaction_start, auto_retry_start
//
// Pi has no built-in subagents or permission prompts; an extension tool that maps to the
// "delegate" category (for example one named "subagent") produces subagent events.

import { categoryFor } from '../categories.js';
import { describeTarget } from '../targets.js';
import { SCHEMA_VERSION } from '../schema.js';

const FRAMEWORK = 'pi';

function base(session, type, extra = {}) {
  return { v: SCHEMA_VERSION, framework: FRAMEWORK, session, agent: 'main', type, ...extra };
}

// Tool results are { content: [{ type: 'text', text }], ... }; only used for error text.
function resultText(result) {
  const first = Array.isArray(result?.content) ? result.content.find((c) => c?.type === 'text') : undefined;
  return typeof first?.text === 'string' ? first.text : undefined;
}

/**
 * @param {string|undefined} session fallback session id, used when the event carries none
 * @param {object} event a Pi event
 */
export function piEventToArena(session, event) {
  if (event === null || typeof event !== 'object') return [];
  const sid = session ?? 'pi';

  switch (event.type) {
    case 'session':
      return [base(typeof event.id === 'string' ? event.id : sid, 'session_start')];

    case 'session_start':
      return [base(sid, 'session_start')];

    case 'agent_start':
    case 'compaction_start':
      return [base(sid, 'thinking')];

    case 'message_update':
      // Fires per token; only the start of a reasoning block matters.
      return event.assistantMessageEvent?.type === 'thinking_start' ? [base(sid, 'thinking')] : [];

    case 'tool_execution_start': {
      if (!event.toolName) return [];
      const category = categoryFor(FRAMEWORK, event.toolName);
      const events = [
        base(sid, 'tool_start', {
          id: event.toolCallId,
          tool: event.toolName,
          category,
          target: describeTarget(event.args),
        }),
      ];
      if (category === 'delegate' && event.toolCallId) {
        events.push(base(sid, 'subagent_start', { id: event.toolCallId }));
      }
      return events;
    }

    case 'tool_execution_end': {
      if (!event.toolName) return [];
      const ok = event.isError !== true;
      const events = [
        base(sid, 'tool_end', {
          id: event.toolCallId,
          tool: event.toolName,
          ok,
          error: ok ? undefined : resultText(event.result),
        }),
      ];
      if (categoryFor(FRAMEWORK, event.toolName) === 'delegate' && event.toolCallId) {
        events.push(base(sid, 'subagent_end', { id: event.toolCallId }));
      }
      return events;
    }

    case 'auto_retry_start':
      return [base(sid, 'error', { message: `retry ${event.attempt}/${event.maxAttempts}` })];

    case 'agent_end':
      return [base(sid, 'done')];

    default:
      return [];
  }
}

export function createPiAdapter() {
  return {
    /** Payload accepted by POST /hook/pi: { session?: string, event: <Pi event> } */
    fromPayload(payload) {
      if (payload === null || typeof payload !== 'object') return [];
      return piEventToArena(payload.session, payload.event);
    },
  };
}
