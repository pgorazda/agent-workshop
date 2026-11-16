// Claude Code adapter: turns hook payloads (live) and transcript lines (replay)
// into canonical Agent Workshop events.
//
// Hook payload fields used: hook_event_name, session_id, tool_name, tool_input,
// tool_response, tool_use_id, message. Field availability differs between Claude Code
// versions, so every field is treated as optional.

import { categoryFor } from '../categories.js';
import { describeTarget } from '../targets.js';
import { SCHEMA_VERSION } from '../schema.js';

const FRAMEWORK = 'claude-code';

export { describeTarget };

// Best-effort: a hook response has no single failure flag across tools and versions.
export function responseFailed(response) {
  if (response === null || typeof response !== 'object') return false;
  return response.is_error === true || response.interrupted === true || Boolean(response.error);
}

function responseError(response) {
  if (response === null || typeof response !== 'object') return undefined;
  const err = response.error ?? response.stderr;
  return typeof err === 'string' && err.length > 0 ? err : undefined;
}

function base(session, type, extra = {}) {
  return { v: SCHEMA_VERSION, framework: FRAMEWORK, session, agent: 'main', type, ...extra };
}

/** Live adapter. Keeps a small per-session stack of open subagents. */
export function createClaudeCodeAdapter() {
  const openSubagents = new Map(); // session -> string[]
  let counter = 0;

  function stack(session) {
    if (!openSubagents.has(session)) openSubagents.set(session, []);
    return openSubagents.get(session);
  }

  function fromHook(payload) {
    if (payload === null || typeof payload !== 'object') return [];
    const session = payload.session_id ?? 'unknown';
    const tool = payload.tool_name;

    switch (payload.hook_event_name) {
      case 'SessionStart':
        return [base(session, 'session_start')];

      case 'UserPromptSubmit':
        return [base(session, 'thinking')];

      case 'PreToolUse': {
        if (!tool) return [];
        const category = categoryFor(FRAMEWORK, tool);
        const events = [
          base(session, 'tool_start', {
            id: payload.tool_use_id,
            tool,
            category,
            target: describeTarget(payload.tool_input),
          }),
        ];
        if (category === 'delegate') {
          const id = payload.tool_use_id ?? `sub-${++counter}`;
          stack(session).push(id);
          events.push(base(session, 'subagent_start', { id }));
        }
        return events;
      }

      case 'PostToolUse':
        if (!tool) return [];
        return [
          base(session, 'tool_end', {
            id: payload.tool_use_id,
            tool,
            ok: !responseFailed(payload.tool_response),
            error: responseError(payload.tool_response),
          }),
        ];

      case 'PostToolUseFailure':
        if (!tool) return [];
        return [
          base(session, 'tool_end', {
            id: payload.tool_use_id,
            tool,
            ok: false,
            error: typeof payload.error === 'string' ? payload.error : undefined,
          }),
        ];

      case 'Notification':
        return /permission/i.test(String(payload.message ?? ''))
          ? [base(session, 'waiting_permission', { message: payload.message })]
          : [];

      case 'SubagentStop': {
        const id = stack(session).pop() ?? 'unknown';
        return [base(session, 'subagent_end', { id })];
      }

      case 'Stop':
        openSubagents.delete(session);
        return [base(session, 'done')];

      default:
        return [];
    }
  }

  return { fromHook };
}

/**
 * Replay adapter: converts the text of a Claude Code transcript (JSONL) into events with
 * timestamps taken from the transcript. Lines that are not understood are skipped.
 */
export function transcriptToEvents(text) {
  const events = [];
  let lastTs;
  let lastSession = 'replay';
  const delegateIds = new Set();

  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }
    if (entry === null || typeof entry !== 'object') continue;

    const session = entry.sessionId ?? lastSession;
    lastSession = session;
    const parsed = Date.parse(entry.timestamp ?? '');
    const ts = Number.isFinite(parsed) ? parsed : lastTs;
    if (ts !== undefined) lastTs = ts;
    const agent = entry.isSidechain ? String(entry.agentId ?? 'sidechain') : 'main';
    const mk = (type, extra) => ({ ...base(session, type, extra), agent, ...(ts !== undefined ? { ts } : {}) });

    const content = entry.message?.content;

    if (entry.type === 'assistant' && Array.isArray(content)) {
      for (const block of content) {
        if (block?.type === 'thinking') {
          events.push(mk('thinking'));
        } else if (block?.type === 'tool_use' && block.name) {
          const category = categoryFor(FRAMEWORK, block.name);
          events.push(
            mk('tool_start', {
              id: block.id,
              tool: block.name,
              category,
              target: describeTarget(block.input),
            }),
          );
          if (category === 'delegate' && block.id) {
            delegateIds.add(block.id);
            events.push(mk('subagent_start', { id: block.id }));
          }
        }
      }
    } else if (entry.type === 'user') {
      if (Array.isArray(content) && content.some((b) => b?.type === 'tool_result')) {
        for (const block of content) {
          if (block?.type !== 'tool_result') continue;
          events.push(mk('tool_end', { id: block.tool_use_id, ok: block.is_error !== true }));
          if (delegateIds.delete(block.tool_use_id)) events.push(mk('subagent_end', { id: block.tool_use_id }));
        }
      } else if (!entry.isMeta) {
        // A real user prompt: the agent starts thinking.
        events.push(mk('thinking'));
      }
    }
  }

  if (events.length > 0) {
    const last = events[events.length - 1];
    events.push({ ...base(last.session, 'done'), agent: 'main', ...(last.ts !== undefined ? { ts: last.ts } : {}) });
  }
  return events;
}
