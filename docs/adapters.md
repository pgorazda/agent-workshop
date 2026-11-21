# Connect an agent

Start the bridge first (`agent-workshop-bridge serve`, see the [README](../README.md#watch-a-real-agent)). Then connect the agent you use. The forwarders post to `http://127.0.0.1:8787`. Set `ARENA_BRIDGE_HTTP` to change that. They time out quickly and never block the agent.

## What leaves each agent

- **OpenCode plugin and Pi extension** send only a few fields (tool names, targets, outcomes), never message text, tool output or file contents.
- **Claude Code hooks and the Hermes script** post the agent's whole hook payload, including tool output, to the bridge on `127.0.0.1`. The bridge keeps only a few fields and broadcasts just those. Nothing is stored.

Whichever you pick, the stream that clients receive contains no message text, tool output or file contents. It can still contain targets (a command line, a file name) and error text. Start the bridge with `--redact-targets` (or `ARENA_REDACT_TARGETS=1`) to drop them before they leave the bridge.

## Claude Code

Live: merge the hooks from [`adapters/claude-code/settings.example.json`](../adapters/claude-code/settings.example.json) into your `~/.claude/settings.json`, or into a project's `.claude/settings.json`. Each hook posts its payload to the bridge with `curl`, with a 1 second timeout and `|| true`, so a bridge that is down never blocks the agent.

Replay a recorded session (timing kept, `--speed 0` for no delays). Your own sessions are in `~/.claude/projects/<project>/<session>.jsonl`:

```bash
agent-workshop-bridge replay session.jsonl --speed 4
```

## OpenCode

Copy [`adapters/opencode/arena.js`](../adapters/opencode/arena.js) to `.opencode/plugins/arena.js` in your project, or to `~/.config/opencode/plugins/` for all projects. It uses the plugin `event` hook, so tool failures, permission prompts and subagents (child sessions) are reported accurately.

## Pi

- Live, any mode: copy [`adapters/pi/arena.ts`](../adapters/pi/arena.ts) to `~/.pi/agent/extensions/arena.ts`, or try it once with `pi -e ./adapters/pi/arena.ts`.
- No install, JSON mode: pipe Pi's event stream through the bridge. `--tee` keeps Pi's own output visible.

  ```bash
  pi --mode json "your prompt" | agent-workshop-bridge ingest pi --tee
  ```

## Hermes Agent

Hermes can run shell commands on its lifecycle events, with a payload much like Claude Code's.

1. Copy [`adapters/hermes/arena-hook.sh`](../adapters/hermes/arena-hook.sh) to `~/.hermes/hooks/arena-hook.sh` and keep it executable.
2. Merge the `hooks:` block from [`adapters/hermes/config.example.yaml`](../adapters/hermes/config.example.yaml) into `~/.hermes/config.yaml`.
3. Hermes asks for consent the first time it sees each hook. For a non-interactive run, start it with `--accept-hooks` (or set `HERMES_ACCEPT_HOOKS=1`).

Hermes runs hooks synchronously and without a shell, so the forwarder is a script that exits 0 within a second whatever happens. It covers tool calls and failures, approval prompts (the sign post), subagents (helper penguins), and turn start and end.

## Agent on another machine

The bridge listens on `127.0.0.1` by default, so the agent, the bridge and the app must run on one machine unless you connect them. Two safe ways:

- **The agent is remote** (an SSH session, a dev container, a remote box) and you watch locally. Keep the bridge on your machine and forward its port with a reverse tunnel:

  ```bash
  ssh -R 8787:127.0.0.1:8787 user@remote
  ```

  The agent's hooks post to `127.0.0.1:8787` on the remote side, and the events reach your local bridge. If you use another port, set `ARENA_BRIDGE_HTTP` in the agent's environment.
- **The app is on another machine than the bridge.** Forward the bridge's port with `ssh -L 8787:127.0.0.1:8787 user@bridge-host`, then start the app as usual. Or start the app with `--bridge=ws://<host>:8787/ws`. With a non-local address the app never starts a bridge itself.

The bridge refuses any request that has an `Origin` header for a name that is not local, so a web page cannot use it. It checks the `Host` header only while it listens on a loopback address. Both tunnels above keep it that way.

Avoid `--host 0.0.0.0`. The bridge has no authentication: anyone who can reach the port can read the event stream, which can contain commands and file names, and can post fake events. If you must open it, do it on a trusted network only, and use `--redact-targets`.

## Known limits

- Claude Code hook payloads do not say which subagent made a call. Subagent work shows as a helper penguin that looks busy, not as that subagent's real calls. OpenCode and Hermes report subagent sessions, so their subagents show their real work.
- The OpenCode, Pi and Hermes adapters follow the published type definitions (`@opencode-ai/sdk` 1.19.5), docs (`@mariozechner/pi-coding-agent` 0.73.1) and source (`hermes-agent` 0.19.0) and are tested with made-up fixtures. None has been run against a live agent yet, and field names may change in newer versions.
- Hermes: the hook payload carries whole tool outputs, so the bridge accepts up to 10 MB per post and forwards only a few fields. Approval prompts carry no session id and are attributed to the session seen last, which can be wrong when several Hermes sessions run at once. Hermes sends a subagent's tool calls with the child session id; this is read from the source and not yet confirmed on a live run. `pre_llm_call` is not used because it carries the whole conversation; "thinking" comes from the first API call of each turn.
- OpenCode's `permission.updated` event (also accepted as `permission.asked`) is the only permission signal used. Pi has no built-in permission prompts, so Pi never shows the sign post.
- Pi has no built-in subagents. A tool that maps to the `delegate` category (for example one named `subagent`) produces helper penguins.
- Tool failure from hooks is a heuristic (`is_error`, `interrupted` or an `error` field). Transcript replay uses `is_error` and is exact.

## Bridge options

| Option | Meaning |
|---|---|
| `--port` | Default 8787. `0` takes a free port |
| `--host` | Default `127.0.0.1` |
| `--redact-targets` | Drop targets and error text before they leave the bridge |

The variables `ARENA_PORT`, `ARENA_HOST` and `ARENA_REDACT_TARGETS` do the same. To see what the bridge sends, connect any WebSocket client to `ws://127.0.0.1:8787/ws`.
