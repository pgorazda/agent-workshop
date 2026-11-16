// Canonical Agent Workshop event schema, version 1.
// Keep in sync with schema/event.schema.json (a test guards the enums).

export const SCHEMA_VERSION = 1;

export const CATEGORIES = [
  'read',
  'search',
  'write',
  'exec',
  'web',
  'delegate',
  'think',
  'ask_permission',
  'other',
];

export const EVENT_TYPES = [
  'session_start',
  'tool_start',
  'tool_end',
  'subagent_start',
  'subagent_end',
  'thinking',
  'waiting_permission',
  'error',
  'done',
];

const MAX_TARGET = 120;
const MAX_ERROR = 200;

const isNonEmptyString = (x) => typeof x === 'string' && x.length > 0;

function truncate(s, max) {
  const str = String(s);
  return str.length > max ? `${str.slice(0, max - 1)}…` : str;
}

/**
 * Fill defaults and clamp long strings. Returns a new object; never mutates the input.
 * Unknown extra fields are kept so newer adapters keep working with older bridges.
 */
export function normalizeEvent(input, { redactTargets = false } = {}) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) return input;
  const e = { ...input };
  if (e.agent === undefined) e.agent = 'main';
  if (e.ts === undefined) e.ts = Date.now();
  if (e.target !== undefined) e.target = truncate(e.target, MAX_TARGET);
  if (e.error !== undefined) e.error = truncate(e.error, MAX_ERROR);
  if (redactTargets) {
    delete e.target;
    delete e.error;
  }
  return e;
}

/**
 * Validate a (normalized) event. Returns a list of error strings; empty means valid.
 * Unknown event types are accepted on purpose: clients fall back to a generic animation.
 */
export function validateEvent(e) {
  if (e === null || typeof e !== 'object' || Array.isArray(e)) return ['event must be an object'];
  const errors = [];
  if (e.v !== SCHEMA_VERSION) errors.push(`v must be ${SCHEMA_VERSION}`);
  if (!isNonEmptyString(e.framework)) errors.push('framework must be a non-empty string');
  if (!isNonEmptyString(e.session)) errors.push('session must be a non-empty string');
  if (!isNonEmptyString(e.agent)) errors.push('agent must be a non-empty string');
  if (!isNonEmptyString(e.type)) errors.push('type must be a non-empty string');
  if (typeof e.ts !== 'number' || !Number.isFinite(e.ts)) errors.push('ts must be a number (epoch ms)');
  if (e.category !== undefined && !CATEGORIES.includes(e.category)) {
    errors.push(`category must be one of: ${CATEGORIES.join(', ')}`);
  }
  if (e.ok !== undefined && typeof e.ok !== 'boolean') errors.push('ok must be a boolean');
  if (e.cost !== undefined && (typeof e.cost !== 'number' || !Number.isFinite(e.cost))) {
    errors.push('cost must be a number');
  }
  for (const key of ['tool', 'target', 'error', 'id', 'message']) {
    if (e[key] !== undefined && typeof e[key] !== 'string') errors.push(`${key} must be a string`);
  }

  switch (e.type) {
    case 'tool_start':
      if (e.category === undefined) errors.push('tool_start requires category');
      if (!isNonEmptyString(e.tool)) errors.push('tool_start requires tool');
      break;
    case 'tool_end':
      if (typeof e.ok !== 'boolean') errors.push('tool_end requires ok');
      break;
    case 'subagent_start':
    case 'subagent_end':
      if (!isNonEmptyString(e.id)) errors.push(`${e.type} requires id`);
      break;
    default:
      break;
  }
  return errors;
}
