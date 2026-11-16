// Maps native tool names to the canonical category set. The game only ever sees categories.

// Lower-cased tool name -> category. Shared by all frameworks.
const DEFAULT_MAP = {
  // read
  read: 'read',
  read_file: 'read',
  readfile: 'read',
  view: 'read',
  cat: 'read',
  notebookread: 'read',
  // search
  glob: 'search',
  grep: 'search',
  find: 'search',
  ls: 'search',
  list: 'search',
  search: 'search',
  codesearch: 'search',
  // write
  edit: 'write',
  multiedit: 'write',
  write: 'write',
  write_file: 'write',
  patch: 'write',
  apply_patch: 'write',
  notebookedit: 'write',
  // exec
  bash: 'exec',
  bashoutput: 'exec',
  killshell: 'exec',
  shell: 'exec',
  exec: 'exec',
  run: 'exec',
  // web
  websearch: 'web',
  webfetch: 'web',
  fetch: 'web',
  browse: 'web',
  // delegate
  task: 'delegate',
  agent: 'delegate',
  subagent: 'delegate',
  // think
  todowrite: 'think',
  todoread: 'think',
  exitplanmode: 'think',
  // ask
  askuserquestion: 'ask_permission',
  question: 'ask_permission',
};

// Per-framework overrides, keyed by framework id. Add entries when a framework's names differ.
const FRAMEWORK_OVERRIDES = {
  'claude-code': {},
  opencode: {},
  pi: {},
  // Hermes Agent tool names (tools/*.py in hermes-agent). Names shared with other frameworks
  // (read_file, write_file, patch) come from the default map.
  hermes: {
    terminal: 'exec',
    process: 'exec',
    execute_code: 'exec',
    read_terminal: 'exec',
    close_terminal: 'exec',
    search_files: 'search',
    session_search: 'search',
    skill_view: 'read',
    skills_list: 'read',
    web_search: 'web',
    web_extract: 'web',
    x_search: 'web',
    delegate_task: 'delegate',
    todo: 'think',
    memory: 'think',
    skill_manage: 'think',
    clarify: 'ask_permission',
  },
};

// Name prefixes per framework, tried after exact names. Hermes has many browser_* tools.
const FRAMEWORK_PREFIXES = {
  hermes: [['browser_', 'web']],
};

export function categoryFor(framework, toolName) {
  if (typeof toolName !== 'string' || toolName.length === 0) return 'other';
  const key = toolName.toLowerCase();
  const exact = FRAMEWORK_OVERRIDES[framework]?.[key] ?? DEFAULT_MAP[key];
  if (exact) return exact;
  const prefixed = FRAMEWORK_PREFIXES[framework]?.find(([prefix]) => key.startsWith(prefix));
  return prefixed ? prefixed[1] : 'other';
}
