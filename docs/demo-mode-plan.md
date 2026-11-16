# Plan: demo mode for the browser client

> **Note (phase G-10):** the Godot client builds demo mode (`--demo=<scene>`, with the timelines in `godot/demo/`; see [the Godot client plan](godot-client-plan.md)). The rules in this plan stay the specification. The browser client is not built: ADR 0008 replaced it.

**State: a plan, nothing built yet.** Demo mode is phase 5 of the [browser client plan](browser-client-plan.md) (ADR 0002). Whether to host it is an open question (see the end).

## What demo mode is

The browser client playing a scripted session by itself, with no bridge and no agent. It is the same page as live mode; only where the events come from changes. It is useful for:

* showing the project on your own machine, offline;
* browser tests that need no bridge;
* recordings;
* working on the client without running an agent.

## How it works

### One page, two sources of events

```
live:  BridgeClient    (WebSocket /ws)       --+
                                               +-->  director  -->  penguins, the 2D view
demo:  TimelinePlayer  (a timeline file)     --+
```

Both give canonical schema v1 events. The director, the penguins and the view do not know which source is in use. `src/timeline-player.js` holds a list of `{ t, event }` and, each frame, hands on the events whose `t` has been reached on the simulation clock. Because it runs on the same clock as everything else, a demo is deterministic, and a recording can drive the same player with fixed steps.

### Starting it

Both ways serve on `127.0.0.1` only:

* `npm run demo` in `web/` serves the page with no bridge and opens `/?demo=claude-code`. It reuses the bridge's static-file code (client plan, choice 2), so files are served the same way in both modes.
* `?demo=<scenario>` on the page the bridge serves (`http://127.0.0.1:8787/?demo=claude-code`) plays a demo while the bridge is running anyway.

Without `?demo=`, the page is in live mode. There is no automatic switch from live to demo: if the bridge is down, the page says `waiting for bridge`. Falling back to a demo silently would make someone think agents were working.

### What it plays

Timelines are made in advance, not in the page. A build script sends scripted hook payloads through the real adapters and saves the canonical events in `web/demo/<name>.json`:

```json
{ "title": "Claude Code fixes a failing test", "duration": 43, "events": [ { "t": 3.4, "event": { "v": 1, "type": "tool_start", "...": "..." } } ] }
```

Making them in advance keeps the page the same code in both modes and the files small, and a test checks them like any other output.

| Scenario | Content | State |
|---|---|---|
| `claude-code` | Search, read, edit, a test run that asks for permission and fails, a subagent, a web search, a fix, tests pass, celebration. About 43 s | To write: the same scripted session as the client's browser test |
| `four-agents` | Claude Code, OpenCode, Pi and Hermes at work at once: four penguins with their cord colours, and OpenCode's subagent doing its own work as a helper. Starts staggered | To write: a script per framework, each through its own adapter |

Start with `claude-code`, because the browser test needs it anyway. `four-agents` shows the point of the project best (one schema, any framework), so it should become the default once it is written.

The scenarios are made up: no real repository, prompts or output.

To watch a real session of your own, use the existing replay with the bridge (`npm run replay -- <transcript.jsonl>`) and the live page; demo mode does not duplicate it.

### Looping and controls

* When a timeline ends, the penguins are removed, the random numbers are seeded again and the timeline starts over. Every loop looks the same.
* A small bar in a corner has a scenario picker, pause, speed (1x, 2x, 4x) and restart. Keys: Space pauses, 1 to 3 set the speed. `?clean=1` hides the bar, for recordings.
* The status text says `demo: <title> (scripted, not a live agent)` where live mode says `connected`.

### Tests

* Unit: the timeline player (events at the right moment, pause, speed, a loop restarts cleanly with the same seed).
* Timelines: valid against the schema, canonical fields only, and building them again gives identical files.
* Browser (Playwright, no bridge): start `npm run demo`, open `?demo=claude-code`, and check that the penguin follows the shared trace (`web/test/expected-trace.json`, from the client plan) and that the page reports no errors. This makes the behaviour test independent of the bridge.

## Phases

| Phase | Content | Needs |
|---|---|---|
| 5a | The timeline player, `?demo=claude-code` on the page the bridge serves, the timeline build script, unit tests | Client phases 1 and 2 |
| 5b | `npm run demo`, the browser test without a bridge | 5a |
| 5c | The `four-agents` scenario | 5a |

## Open question: hosting

The repository will be public, so a hosted demo is possible: the page with a scenario, as a link anyone can open. Nothing is decided yet. Things to decide:

1. Host the demo or not, and where (for example GitHub Pages, published by a GitHub Actions workflow)?
2. A hosted page needs a static build, a deploy workflow and publishing checks: no real paths, names or transcripts in it, no requests to other sites, and a notice that it is scripted.
3. Should a hosted page ever connect to a bridge on the visitor's machine? Today the answer is no: the bridge accepts only its own origin (client plan, choice 3), and a hosted demo plays without a bridge.

Dropping a transcript on the page is not planned: `npm run replay` already does this with the bridge.
