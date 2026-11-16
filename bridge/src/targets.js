// Picks the most useful single string describing what a tool call acts on.
// Handles the argument names used by Claude Code, OpenCode and Pi.

function basename(p) {
  return String(p).split(/[\\/]/).pop();
}

export function describeTarget(input) {
  if (input === null || typeof input !== 'object') return undefined;
  const file = input.file_path ?? input.filePath ?? input.notebook_path;
  if (file) return basename(file);
  if (input.command) return String(input.command).split('\n')[0];
  if (input.pattern) return String(input.pattern);
  if (input.url) return String(input.url);
  if (input.query) return String(input.query);
  if (input.description) return String(input.description);
  if (input.goal) return String(input.goal);
  if (Array.isArray(input.urls) && typeof input.urls[0] === 'string') return input.urls[0];
  if (input.path) return basename(input.path);
  return undefined;
}
