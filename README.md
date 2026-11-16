# Agent Workshop

[Polski](README.pl.md)

Watch AI coding agents work as penguins in a pixel-art workshop.

![The Godot client: an agent thinks, uses the forge with a helper, waits for approval and completes its turn](docs/images/agent-workshop.gif)

Agent activity (tool calls, subagents, permission prompts, errors) is turned into a small, framework-neutral event stream. A local bridge streams it to the Godot client, where a penguin walks between workshop stations and uses a different tool for each kind of work. Claude Code, OpenCode, Pi and Hermes Agent are supported through small adapters.

This project is mostly for fun. It is a way to watch agents work, and it is not a monitoring tool. The look and the music come from Polish folk art and dances. See [The look and the sound](#the-look-and-the-sound).

```
Claude Code hooks / OpenCode plugin / Pi extension or JSON stream / Hermes shell hooks / transcript replay
        |
   adapter (maps native events and tool names to the canonical schema)
        |
   bridge  --  POST /event, POST /hook/claude-code   (HTTP in)
        |      WS /ws                                (WebSocket out)
        v
   Godot client (godot/): one penguin per framework + session + agent, drawn in 2D pixel art
```

When one room gets full, more rooms (arenas) open next to it. One arena is on screen at a time, and a camera moves between them.

![Several arenas in the Godot client: the camera slides to a new arena, an approval brings it back, and the overview behind Tab](docs/images/arena-2d-arenas.png)

## Status

| Part | State |
|---|---|
| Event schema v1 (`schema/`) | Done |
| Bridge, adapters for Claude Code, OpenCode, Pi and Hermes, transcript replay (`bridge/`) | Done, covered by 45 automated tests |
| OpenCode plugin, Pi extension, Hermes hook script (`adapters/`) | Written against the published type definitions, docs and source, tested with fixtures. **Not yet run inside a real OpenCode, Pi or Hermes** |
| Godot client (`godot/`) | **Done for desktop: phases G-0 to G-9 of [the plan](docs/godot-client-plan.md).** It plays a live session from the bridge, with the arenas, the interface and the sound, and it plays seven made-up scenes with no bridge. `godot/tools/record.mjs` records each scene as a clip. `node godot/tools/export.mjs --platform windows` builds an unsigned Windows app. **Not done:** Linux and macOS builds, tablets and phones (all postponed), and a measurement on the low-end reference laptop. See [`godot/README.md`](godot/README.md) |
| Browser client (`web/`) | **Not built.** ADR 0008 replaced it with the Godot client. [Its plan](docs/browser-client-plan.md), [the 2D view plan](docs/2d-view-plan.md), [the arenas plan](docs/2d-arenas-plan.md) and [the demo mode plan](docs/demo-mode-plan.md) stay as the specification of the look and the rules |

The plans mention architecture decision records (ADRs) by number, for example ADR 0003. The ADRs are kept outside this repository.

## Quick start

### 1. Run the bridge (Node 20+)

```bash
cd bridge
npm install
npm test
npm start            # http://127.0.0.1:8787, WebSocket path /ws
```

The bridge listens on `127.0.0.1` only. Events can contain commands and file names; start it with `--redact-targets` (or `ARENA_REDACT_TARGETS=1`) to drop targets and error text before they leave the bridge.

The Godot client reads the stream (see "3. Run the Godot client"). To see what the bridge sends, you can also connect any WebSocket client to `ws://127.0.0.1:8787/ws`.

### 2. Feed it events

Pick the agent you use. What leaves each agent differs:

- **OpenCode plugin and Pi extension** send only a few fields (tool names, targets, outcomes), never message text, tool output or file contents.
- **Claude Code hooks and the Hermes script** post the agent's whole hook payload, including tool output, to the bridge on `127.0.0.1`. The bridge keeps only a few fields and broadcasts just those. Nothing is stored. Use `--redact-targets` to also drop targets and error text.

Whichever you pick, the stream clients receive contains no message text, tool output or file contents.

Replay a recorded Claude Code transcript (timing preserved, `--speed 0` for no delays):

```bash
cd bridge
npm run replay -- ../schema/examples/claude-code-transcript.jsonl --speed 4
# your own sessions: ~/.claude/projects/<project>/<session>.jsonl
```

**Claude Code** (live): merge the hooks from [`adapters/claude-code/settings.example.json`](adapters/claude-code/settings.example.json) into your `~/.claude/settings.json` (or a project `.claude/settings.json`). Each hook posts its payload to the bridge with `curl`, with a 1 second timeout and `|| true`, so the bridge being down never blocks the agent.

**OpenCode** (live): copy [`adapters/opencode/arena.js`](adapters/opencode/arena.js) to `.opencode/plugins/arena.js` in your project, or to `~/.config/opencode/plugins/` for all projects. It uses the plugin `event` hook, so tool failures, permission prompts and subagents (child sessions) are reported accurately.

**Pi** (live, any mode): copy [`adapters/pi/arena.ts`](adapters/pi/arena.ts) to `~/.pi/agent/extensions/arena.ts`, or try it once with `pi -e ./adapters/pi/arena.ts`.

**Pi** (no install, JSON mode): pipe Pi's event stream through the bridge CLI. `--tee` keeps Pi's own output visible.

```bash
pi --mode json "your prompt" | node bridge/src/cli.js ingest pi --tee
```

**Hermes Agent** (live): Hermes can run shell commands on its lifecycle events, with a payload much like Claude Code's. Copy [`adapters/hermes/arena-hook.sh`](adapters/hermes/arena-hook.sh) to `~/.hermes/hooks/arena-hook.sh` (keep it executable) and merge the `hooks:` block from [`adapters/hermes/config.example.yaml`](adapters/hermes/config.example.yaml) into `~/.hermes/config.yaml`. Hermes asks for consent the first time it sees each hook; for a non-interactive run start it with `--accept-hooks` (or set `HERMES_ACCEPT_HOOKS=1`). Hermes runs hooks synchronously and without a shell, which is why the forwarder is a script that exits 0 within a second whatever happens. It covers tool calls and failures, approval prompts (sign post), subagents (helper penguins) and turn start and end.

The OpenCode plugin, the Pi extension and the Hermes script post to `http://127.0.0.1:8787` by default; set `ARENA_BRIDGE_HTTP` to change it. Like the Claude Code hooks, they time out quickly and never block the agent.

### 3. Run the Godot client

You need Node 20 or later and the Godot editor in the pinned version (the file `godot/GODOT_VERSION`). Set `GODOT` to your editor, or let `node godot/tools/get-godot.mjs` download it. `godot/README.md` tells the details.

```bash
cd bridge && npm start                                                              # the bridge
cd godot && "$GODOT" --path .                                                       # the client (import the project once: "$GODOT" --headless --path . --import)
cd bridge && npm run replay -- ../schema/examples/claude-code-transcript.jsonl --speed 4   # events for the client
cd godot && "$GODOT" --path . -- --demo=multi                                       # a made-up scene, no bridge (also session, arenas, many, follow, ten, tour)
```

The client shows one room. Each agent that sends an event gets a penguin. With more agents than one room holds, more rooms (arenas) open and a camera moves between them. Start the client first, then the replay: the bridge keeps no history. Keys, options and the sound are in `godot/README.md`. The scenes (`--demo=<name>`, or the key D in the app):

| Scene | What it plays |
|---|---|
| `session` | One Claude Code session |
| `multi` | Six agents at once in one room |
| `arenas` | Nine agents in three arenas, with a camera between them |
| `many` | Nine arenas on three pages of four |
| `ten` | Forty arenas on ten pages |
| `follow` | The switch that chooses what moves the camera, and its pace |
| `tour` | A guided tour of one arena: it stops at each event and at each station, and a callout explains what you see |

To record a scene as a 1920×1080 clip, or to save stills (this makes the images in `docs/images/`), you need a window and `ffmpeg`:

```bash
cd godot && node tools/record.mjs --scene arenas      # out/arenas.mp4
cd godot && node tools/record.mjs --scene multi --stills 19.5 --no-switch    # out/still-multi-19.5.png
```

To get an app that runs with no editor (Windows only; unsigned):

```bash
cd godot && node tools/export.mjs --platform windows     # out/export/windows/AgentWorkshop.exe
```

The first run downloads the export templates (about 1.3 GB). The app takes the same options as the editor, after `--`.

### 4. Run the tests

```bash
cd bridge && npm test
cd godot && node tools/run-gut.mjs    # GUT tests, headless
cd godot && node --test               # Node tests: bridge link, license split, tools
cd godot && node tools/check.mjs      # GDScript check, warnings count as errors
```

The `godot/` commands need Node 20 or later and `GODOT`.

## Event schema

`schema/event.schema.json` is the contract between the adapters and the client. The client picks stations from `category` only, never from tool names:

| `category` | Station | Example Claude Code tools |
|---|---|---|
| `read` | Bookshelf | Read |
| `search` | Map table | Grep, Glob |
| `write` | Workbench | Edit, Write |
| `exec` | Forge | Bash |
| `web` | Telescope | WebSearch, WebFetch |
| `delegate` | Helper desk (a helper penguin appears) | Task |
| `think` | Thinking chair | TodoWrite |
| `ask_permission` | Sign post | AskUserQuestion |
| `other` or unknown | Odd jobs | MCP tools, anything unmapped |

Also: `tool_end` with `ok: false` makes the penguin flop, `waiting_permission` sends it to the sign post, `done` starts a celebration. Unknown event types are accepted and shown as generic work.

## Adding an agent framework

1. Write an adapter in `bridge/src/adapters/` that turns the framework's native events into schema v1 events. Use `categoryFor()` from `bridge/src/categories.js` and `describeTarget()` from `bridge/src/targets.js`. Add per-framework tool-name overrides to `categories.js` if needed. `opencode.js`, `pi.js` and `hermes.js` are short, complete examples.
2. Register it in the `adapters` table in `bridge/src/server.js`; that gives it a `POST /hook/<framework>` route. Or run it beside the agent and `POST` canonical events to `/event`.
3. Ship a small forwarder for the agent (hook config, plugin or extension) that sends only the fields the adapter needs, and put it in `adapters/<framework>/`.
4. Give the framework a cord colour in the client's director. The colours are listed in [the browser client plan](docs/browser-client-plan.md).

The client logic does not change. To report subagent activity so it reaches the helper penguin, send `subagent_start` with an `id`, then use that same `id` as the `agent` of the subagent's own events (OpenCode does this).

## The look and the sound

The room is drawn in a look of its own, at 480×270 pixels. It is inspired by the penguin's cap, the rogatywka from Kraków, and by Polish folk art: the painted flowers of Zalipie, folk painting from Lipnica Murowana, Bolesławiec pottery and kilim rugs. The pictures are PNG files, and the code that draws them is in `godot/art/image_src/`. It is not MIT: see [License](#license). The pixel fonts are Tiny5 and Silkscreen (SIL OFL 1.1).

The client plays four original tunes in the manner of Polish folk dances (krakowiak, kujawiak, oberek and góralski) and five event sounds (a hammer's tink, the desk bell, a flop, a chime and a fanfare). They are WAV files that `godot/tools/render-sound.mjs` renders from `godot/art/sound_src/sound.js`. All sound starts off.

## Layout

```
schema/          event.schema.json and example sessions for Claude Code, OpenCode, Pi and Hermes (synthetic, built from the documented formats)
bridge/          Node bridge: schema validation, categories, adapters (Claude Code, OpenCode, Pi, Hermes), server, CLI, tests
adapters/        forwarders that run inside or beside each agent: Claude Code hooks, OpenCode plugin, Pi extension, Hermes hook script
godot/           the Godot client: project, bridge link, scenes, tools and tests (GUT is kept in godot/addons/gut/, MIT)
godot/art/       the Godot client's art: drawing code, rendered images and sounds (all rights reserved, see LICENSE-ASSETS)
godot/demo/      the seven made-up scenes (JSON timelines)
docs/            the plan of the Godot client, and the plans of the browser client, its demo mode, its 2D view and its arenas (the rules stay the specification)
docs/images/     preview images made with the Godot client (all rights reserved, see LICENSE-ASSETS)
```

## Known limits

- Claude Code hook payloads do not identify which subagent made a call, so subagent work shows up as a helper penguin that looks busy, not as that subagent's real calls. OpenCode and Hermes report subagent sessions, so their subagents show their real work.
- The OpenCode, Pi and Hermes adapters follow the published type definitions (`@opencode-ai/sdk` 1.19.5), docs (`@mariozechner/pi-coding-agent` 0.73.1) and source (`hermes-agent` 0.19.0) and are tested with synthetic fixtures. None has been run against a live agent yet, and field names may change in newer versions.
- Hermes: the hook payload comes with whole tool outputs, so the bridge accepts up to 10 MB per post and forwards only a few fields. Approval prompts carry no session id and are attributed to the session seen last, which can be wrong when several Hermes sessions run at once. Hermes sends a subagent's tool calls with the child session id; this is read from the source and not yet confirmed on a live run. `pre_llm_call` is not used because it carries the whole conversation; "thinking" comes from the first API call of each turn.
- OpenCode's `permission.updated` event (also accepted as `permission.asked`) is the only permission signal used; Pi has no built-in permission prompts, so Pi never shows the sign post.
- Pi has no built-in subagents. A tool that maps to the `delegate` category (for example one named `subagent`) produces helper penguins.
- Tool failure from hooks is a heuristic (`is_error`, `interrupted` or an `error` field); transcript replay uses `is_error` and is exact.

## License

- **Code:** MIT. See [LICENSE](LICENSE).
- **Art:** all rights reserved. This covers the drawing and sound code in `godot/art/` (and later `web/src/view2d/art/`), the images and sounds in it, the images in `docs/images/`, and images, video or sound made with them. See [LICENSE-ASSETS](LICENSE-ASSETS).

The fonts Tiny5 and Silkscreen come from npm and are under the SIL Open Font License 1.1.
