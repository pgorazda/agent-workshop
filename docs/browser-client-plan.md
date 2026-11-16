# Plan: the browser client

> **Note (phase G-10):** the browser client is not built. ADR 0008 replaced it with the Godot client (see [the Godot client plan](godot-client-plan.md)), which builds the 2D view and demo mode. The rules in the other plans stay the specification. The origin and host checks for the bridge are still worth doing.

**State: a plan, nothing built yet.** The decision is ADR 0002 (proposed). What the client draws is ADR 0003: a 2D pixel-art view, planned in [the 2D view plan](2d-view-plan.md). Its demo mode is planned in [the demo mode plan](demo-mode-plan.md).

## Goal

A client in `web/`. Start the bridge, open `http://127.0.0.1:8787/` and watch the workshop. The client reads the bridge's WebSocket stream. There is no engine to install, it runs in any browser, and it can be tested and recorded headless in the cloud environment.

Not in scope: changes to the schema or the adapters, a 3D view (ADR 0003), navigation meshes, skeletal animation.

## What already exists

| Piece | Where it is now | What to do with it |
|---|---|---|
| Event stream | bridge, `WS /ws` | Use as it is |
| Event schema | [`schema/event.schema.json`](../schema/event.schema.json) | Parse the same fields |
| Recorded sessions | [`schema/examples/`](../schema/examples/) | Fixtures for the tests |
| The room, the penguin and its poses, the effects, the activity log, the rules for several agents and several arenas | The JavaScript mockup; now the Godot client in `godot/` | The 2D view; see the 2D view plan |

## Design

### Layout

```
web/
  index.html              the canvas, import map
  package.json            fonts (exact versions), scripts: test, e2e, demo
  src/
    main.js               start-up: the view, the frame loop, wiring
    config.js             URL options: ?demo=<scenario>, ?debug=1, and the 2D view's options
    clock.js              the simulation clock (now, dt)
    rng.js                seeded random numbers (mulberry32, seed 7)
    event.js              one canonical event: parse, actorKey, kind
    bridge-client.js      WebSocket, reconnect every 2 s, at most 64 events per frame
    stations.js           the station table (see below)
    penguin-actor.js      the event queue and the behaviour (generators): position, facing, pose
    director.js           one penguin per framework/session/agent, helpers, cord colours, the limit of 12 penguins
    timeline-player.js    demo mode (see the demo mode plan)
    view2d/               the 2D view (see the 2D view plan)
  test/                   node --test unit tests, the Playwright test, expected-trace.json
```

### The station table

Nine stations, one per category. Positions are floor coordinates in metres (x to the right, z to the back wall). A penguin stands 2.2 m in front of a station's prop, on the side that faces the middle of the room. The 2D view projects this table onto the screen.

| Station | Category | Pose | Position (x, z) |
|---|---|---|---|
| Bookshelf | `read` | browse | (−7, 3) |
| Map table | `search` | browse | (−4, 6) |
| Workbench | `write` | hammer | (0, 7) |
| Forge | `exec` | shovel | (5, 5) |
| Telescope | `web` | telescope | (7, 0) |
| Helper desk | `delegate` | browse | (5, −5) |
| Thinking chair | `think` | think | (−5, −5) |
| Sign post | `ask_permission` | sign | (0, −7) |
| Odd jobs | `other` | hammer | (−7, −2) |

Cord colours, by framework: claude-code `#d97333`, opencode `#3380e6`, pi `#994dcc`, hermes `#e6bf33`.

### Choices

1. **No build step.** Plain ES modules and an import map. Every package (today only the two fonts) is installed with npm at an exact version and served locally, so nothing is fetched from a CDN at run time and the page works offline. Only `main.js`, `bridge-client.js` and the 2D view touch the DOM, so Node tests import every other module directly. Types come from JSDoc with `// @ts-check`. If the client grows past about 2,000 lines, revisit Vite and TypeScript.

2. **The bridge serves the page.** `GET /` returns `web/index.html`, and the page's own files and packages come from `web/`. Only GET, only that folder, and paths that leave it are refused. The page and `/ws` then share an origin, so the page connects to `ws://<its own host>/ws` with no settings. The page always talks to the bridge that served it: to watch another bridge, open that bridge's address. One process, one URL: `npm start` in `bridge/`, then open the browser.

3. **Lock the bridge to its own origin first.** Today `/ws` accepts a connection from any origin, and the POST routes parse the body whatever its content type. WebSockets are not covered by CORS, and a cross-site POST with a plain-text body needs no preflight, so a web page open in the same browser may be able to read the stream (which carries commands and file names) or inject events. This is not new with the browser client, but serving a page from the bridge is the moment to fix it:
   * a WebSocket upgrade is accepted with no `Origin` header (scripts and other native clients) or with the bridge's own origin;
   * a POST with an `Origin` header from another origin is refused (the forwarders send none);
   * the `Host` header must name the bridge's own address, which stops DNS rebinding.

   There are no exceptions for pages served from elsewhere. A hosted demo, if there ever is one, plays without a bridge (see the demo mode plan).

   Needs checking: whether current browsers' local network access rules already block some of this.

4. **One simulation clock.** Every module reads `clock.now` and `clock.dt`, never `performance.now()`. In the page the frame loop advances the clock by the frame time, clamped to 0.1 s. Tests and recordings advance it by fixed steps.

5. **Behaviour as generators.** `yield` waits one frame. It is deterministic, and a test can step it frame by frame.

6. **The actor does not draw.** It exposes position, facing and pose for each penguin, and the view draws them. This keeps the door open for another view (ADR 0003).

7. **Hidden tabs.** A browser stops drawing a tab in the background, but its WebSocket keeps receiving, so a penguin can come back to hundreds of queued events. When a penguin's queue is longer than a limit (about 20) in the first frame after the tab is shown again, drop its oldest finished tool calls and keep the last few events, any open permission prompt and the `done`. The clamp in choice 4 stops a jump.

8. **Keys and debug.** Tab opens the overview of arenas (the arenas plan); the page stops the browser from moving focus with it. The page has no other controls to reach with Tab, and the address bar stays reachable with F6 or Ctrl+L. `?debug=1` logs events, poses and the frame rate, and exposes `window.__agentWorkshop` (penguins, poses, positions) for the tests.

## Testing

* **Unit tests** (`cd web && npm test`, `node --test`, no browser):
  * parsing events;
  * the director: one penguin per key, `hello` ignored, a helper per `subagent_start` and removed after `subagent_end`, a subagent's own events going to its helper, the limit of 12;
  * the actor, stepped with a fake clock: `tool_start` walks to the right station and takes its pose, `tool_end` with `ok: false` flops, a queue makes it hurry, the backlog rule of choice 7.
* **Browser test** (`npm run e2e`, Playwright with headless Chromium): start a bridge on a free port, open the page, wait for `connected`, play a scripted Claude Code session into the bridge at 4× speed, and check that there are no page errors and that the penguin goes through the session in order (map table, bookshelf, workbench, forge, sign post, flop, helper desk and its helper, telescope, workbench, forge, celebration), read from `window.__agentWorkshop`. Take screenshots at a few moments to look at, not to compare pixels. The scripted session (hook payloads with times, sent through the real Claude Code adapter) and the driver that posts it to the bridge are still to write.
* **Bridge tests:** serving files (content types, paths that leave the folder refused, the page missing when `web/` is absent), and the origin and host checks.
* **The expected behaviour:** write down what the penguin should do in the scripted session, as a shared trace (`web/test/expected-trace.json`: for each event, the station and the pose). The browser test and the demo test check the client against it.
* **Recording:** `web/record.mjs`: bridge, page, scripted session, captured frames, mp4.

## Phases

Each phase is one commit or pull request that leaves every test green.

| Phase | Content | Done when |
|---|---|---|
| 0. Bridge | Origin and host checks, serving `web/`, with tests | The bridge tests pass; a foreign origin is refused |
| 1. A page that connects | `index.html`, `main.js`, `config.js`, `event.js`, `bridge-client.js`; the connection state and the events as text | Open `http://127.0.0.1:8787/`: `connected`, and events listed as they arrive. Smoke test in the browser |
| 2. Behaviour | `clock.js`, `rng.js`, `stations.js`, `penguin-actor.js`, `director.js`, the scripted session and its driver, the shared trace | Unit tests for the actor and the director; the browser test follows the shared trace through `window.__agentWorkshop` |
| 3. Background tab, resizing, debug | Choices 7 and 8 | Tests for the backlog rule; a hidden tab comes back without a long replay |
| 4. Recording and documents | `record.mjs`; README (quick start, status, layout); ADR 0002 updated with what was verified | A clip of the real client against the real bridge |
| 5. Demo mode | The page plays a scripted session with no bridge: `?demo=<scenario>`, and `npm run demo` in `web/`. Details and sub-phases in [the demo mode plan](demo-mode-plan.md) | `npm run demo` plays the scripted session on `127.0.0.1` with no bridge running |

The 2D view's phases (the 2D view plan) start after phase 1 and need phase 2 for the penguins.

Rough size: 600 to 800 lines of JavaScript in `web/src/` outside the 2D view; about 300 lines of tests; about 100 lines in the bridge.

## Risks

* An origin check that is too strict could lock out a forwarder or script that does send an `Origin` header.
* Speed is unknown on real hardware: the tests use software rendering.
* The actor may grow assumptions about how it is drawn. Keep its view of the world to position, facing and pose.
