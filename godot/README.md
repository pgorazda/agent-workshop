# Agent Workshop: the Godot client

This folder holds the Godot client of Agent Workshop. It reads the event stream of the bridge and, in
later phases, shows the workshop. The plan is in [`docs/godot-client-plan.md`](../docs/godot-client-plan.md).

**State: phase G-9 (exports), for Windows only: see "Phase G-9" below. The app is built as one unsigned `.exe`, and Linux and macOS are postponed by the owner.** Phase G-8 (replay, recording and the tour): The client records every scene as a clip, with a recording mode, a Linux container, a check that two runs give the same frames, and the scene `tour` (see "Phase G-8" below). The app plays the sound files: a tune, event sounds, a sound switch in the top right with its menu, and the keys M and S (see "Phase G-7" below; nobody has listened to the sound yet, and all sound starts off). The app has its bar, cards, number chips, focus ring and label, notices, tabs, page boxes, follow
switch and menu, keys and mouse (see "Phase G-6" below). It shows the arenas of a live session through a camera that slides, flies, zooms and scrolls
(see "Phase G-5" below). It reads the bridge, or it plays a made-up scene from `demo/` (see "Phase G-4" below). The rules of the arenas are ported to GDScript and
tested against the JavaScript of the mockup (see "Phase G-1"). The pictures of the workshop are rendered to PNG files by
the art code of the mockup, and a gallery shows them (see "Phase G-2"). The room, the stations and the spots are in
"Phase G-3". The text view of the events (phase G-0) is still there as `src/main.tscn`.

**The sections of the phases G-1 to G-9 below are the record of what was done then.**

## Folders

| Path | Content |
|---|---|
| `GODOT_VERSION` | The pinned Godot version (standard build, not .NET). |
| `project.godot` | 2D only, Compatibility renderer, 480x270 viewport, integer scaling, nearest filtering. |
| `src/core/` | Classes with no nodes and no drawing: `event.gd` (one schema v1 event), `options.gd` (command line), `arena_rules.gd` (arena model and camera rules), `rng.gd` (mulberry32). `stations.gd` (the station table) and `spots.gd` (spots and the queue). Phase G-4: `clock.gd`, `director.gd`, `penguin_actor.gd`, `world.gd`, `effects.gd` (effect cues and the shake), `focus.gd`, `backlog.gd`, `frame_policy.gd`. |
| `src/net/` | `bridge_client.gd`: the WebSocket link to the bridge. `timeline_player.gd`: demo mode. |
| `src/core/camera.gd`, `src/core/bench_log.gd`, `src/view/arena_view.gd` | Phase G-5: the incremental camera, the benchmark log, and the camera view. See "Phase G-5". |
| `src/live.tscn`, `src/view/live_view.gd` | The live view of phases G-4 and G-5. It is the main scene. `src/view/penguin_view.gd` turns an actor into what the art node draws. |
| `src/core/log_model.gd`, `bar_layout.gd`, `startup_report.gd`, `src/view/interface_model.gd`, `ui_input.gd`, `art/ui_kit.gd`, `crowd_art.gd`, `bar_art.gd`, `overview_art.gd` | Phase G-6: the log and the cards, the places of the bar, the model and the hit tests of the interface, the keys and clicks, and the drawing of the interface. See "Phase G-6". |
| `src/core/sound_model.gd`, `src/view/sound_player.gd`, `art/sound_ui_art.gd`, `art/sound/`, `tools/sound-levels.mjs` | Phase G-7: the sound state and the rules for the event sounds, the players and the master limiter, the sound switch and its menu, the sound files (phase S-4), and the levels tool. See "Phase G-7". |
| `src/core/recording.gd`, `tour.gd`, `trace_log.gd`, `src/view/tour_holes.gd`, `art/pointer_art.gd`, `art/tour_art.gd`, `tools/record.mjs`, `determinism.mjs`, `Dockerfile` | Phase G-8: the recording mode, the tour, the trace of visits, the mouse pointer and key caps of the scripted scenes, the recorder, the same-frames check and the Linux recorder. See "Phase G-8". |
| `export_presets.cfg`, `tools/export.mjs`, `tools/export.test.mjs`, `art/images/app_icon.png` | Phase G-9: the export presets, the export tool (templates and export), its tests and the app icon. Windows only: see "Phase G-9". |
| `src/main.tscn`, `src/main.gd` | The text view of the connection and the events (phase G-0). |
| `demo/` | The scene timelines (JSON, made up): `session`, `multi` (phase G-4), `arenas`, `many`, `follow` and `ten` (phase G-5), and `tour` (phase G-8). |
| `art/` | The art. It is not MIT: see `LICENSE-ASSETS`. It holds the drawing code (`draw_kit.gd`, `text_art.gd`, `room_art.gd`, `room_stage_art.gd`, `atlas.gd`, `gallery_art.gd`), the generated `atlas_data.gd`, the PNG files in `images/`, their source in `image_src/`, and `MANIFEST.txt` (hashes). See "Phase G-2". |
| `src/gallery.tscn` | A scene that shows every picture of the atlas and a line of text. |
| `src/room.tscn`, `src/view/room_view.gd` | The room view of phase G-3: one room, with a penguin at each station. |
| `addons/gut/` | GUT 9.7.1 (MIT), kept in the repository. It is the branch `godot_4_7` of GUT. |
| `test/` | GUT tests. `test/fixtures/` holds the example sessions as canonical events and the golden data of the arena rules. `test/support/` holds helpers for the tests. |
| `spikes/s6/` | Spike S-6: the benchmark of rooms as a `SubViewport` each or as one world. See "Spike S-6". |
| `tools/` | Node scripts and tests (see below). |

## Set up

You need two things.

1. **Node 20 or later.** The scripts and the bridge use it. Run `npm ci` in `bridge/` once.
2. **The Godot editor, in the pinned version.** Use one of these ways:
   * Set the environment variable `GODOT` to your editor. Use the console build on Windows
     (`Godot_v<version>-stable_win64_console.exe`), because it prints to the terminal.

     ```bash
     export GODOT=/path/to/godot          # macOS, Linux, Git Bash
     ```

     ```powershell
     $env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"   # PowerShell
     ```
   * Or download the pinned version into `godot/.editor/` (git-ignored). The script checks the SHA-512
     hash of the archive. It does nothing when `GODOT` is set.

     ```bash
     cd godot && node tools/get-godot.mjs
     ```

The scripts use `GODOT` first. If it is not set, they use the downloaded copy. The path of an editor
never goes into the repository.

## Run

Start a bridge, then the app:

```bash
cd bridge && npm start                 # the bridge, on 127.0.0.1:8787
cd godot && "$GODOT" --path .          # the app (import the project once: "$GODOT" --headless --path . --import)
cd bridge && npm run replay -- ../schema/examples/claude-code-transcript.jsonl --speed 4   # events for the app
```

The app shows one room. Each agent that sends an event gets a penguin, and the penguin walks through the stations. The bridge keeps no
history, so start the app first and then the replay. To play a scene with no bridge:

```bash
cd godot && "$GODOT" --path . -- --demo=session     # or --demo=multi
```

Keys (phase G-6, the full list and the mouse are in "Keys and mouse" of that section): F switches between AUTO and MANUAL, Tab opens and closes the
overview, Esc leaves it, Left and Right go to another arena (another page in the overview), N goes to the arena that needs you. Sound (phase G-7, all of it starts off): M turns all sound on or off, S opens the sound menu (1 to 4 pick a tune, 0 none, E the event sounds, Esc closes it). In demo mode
Space pauses, 1 to 3 set the speed (1x, 2x, 4x) while the follow menu and the sound menu are closed, and `[` and `]` change it (0.5, 1, 2, 4). R starts the scene again, D opens the list of scenes
(Up, Down, Enter, Esc), C hides the bar. A scene starts again two and a half seconds after its end. A click on a tab, a page box, an arena in the
overview, a penguin or a card does what it says; the follow switch opens its menu.

Command-line options come after `--`:

| Option | Meaning |
|---|---|
| `--bridge=ws://127.0.0.1:8787/ws` | The bridge address. This value is the default. |
| `--log-events` | Also print each state change and each event to standard output. Use it with `--headless`. |
| `--demo=<name>` | Play the scene `demo/<name>.json` instead of reading the bridge. |
| `--timeline=<path>` | Play a timeline file of your own (for example one in `user://`). It wins over `--demo`. |
| `--speed=<n>`, `--paused` | The speed of the simulation (1 is real time), and the clock paused at the start. |
| `--at=<seconds>` | Run the simulation this long before the first frame. For screenshots: `--demo=multi --at=9.5 --paused`. |
| `--clean` | Hide the status bar. |
| `--limit=<n>` | The most penguins in all arenas (200 by default; the director on its own has 12). |
| `--arena-size=<n>` | The agents in an arena (4 by default, 0 for one room for everyone). It wins over the `options` of a scene file. |
| `--leave-after=<s>` | The seconds after which a quiet agent leaves (600 by default, 0 for never). |
| `--follow=manual` | Start the camera in MANUAL. |
| `--benchmark=<scene>`, `--benchmark-out=<file>`, `--vsync=on\|off` | Play a scene in real time and write a CSV of the frames (phase G-5). |
| `--unfocused-fps=<n>`, `--focused-fps=<n>` | The frame rate of a window with no focus (30 by default) and with focus (60 by default). 0 is no cap. |
| `--frame-stats` | Print the average cost of the parts of a frame every 5 s (phase G-6). |
| `--startup-report=<file>` | Write the times of the start-up to a file after the first frames, and quit (phase G-6). |
| `--reduced-motion` | The room does not shake after a failure. |
| `--sound=<tune>\|on\|events\|off` | Start with sound on: a tune (krakowiak, kujawiak, oberek, goralski), `on` (the default tune and the event sounds), `events` (event sounds only). All sound is off without it (phase G-7). |
| `--record-fps=<n>`, `--record` | Recording mode at `n` frames a second (30 for `--record`). Started by `tools/record.mjs` together with the engine's `--write-movie` and `--fixed-fps`. See "Phase G-8". |
| `--stills=<s,...>`, `--stills-out=<folder>` | Recording mode: run with no drawing up to each time, draw one frame, and save it as `still-<n>.png`. |
| `--menu=<s>`, `--events=0`, `--no-switch` | Recording: the sound menu is open for the first seconds, no event sounds (the tune plays), and no sound switch. |
| `--trace` | Print `[trace] <who>: <station>` when a penguin begins to visit a station (phase G-8; `tools/replay.test.mjs` reads it). |

Example: `"$GODOT" --headless --path . -- --bridge=ws://127.0.0.1:9000/ws --log-events`.

The client tries again every 2 seconds when the connection is lost. It reads at most 64 events in a
frame. It ignores the `hello` message that the bridge sends to a new connection. It accepts an event
with an unknown `type` as generic work.

## Test

```bash
cd godot
npm test             # the GUT tests, then all Node tests
node tools/check.mjs # GDScript check: warnings count as errors
```

| Command | What it does |
|---|---|
| `node tools/run-gut.mjs` | Imports the project, then runs the GUT tests headless (`test/`). It exits with code 1 when a test fails, when GUT ignores a script (a parse error), and, for a run of all tests, when fewer scripts ran than there are `test_*.gd` files. Extra arguments go to GUT, for example `-gselect=event`. |
| `node --test` | All Node tests in `tools/`: the bridge link, the license check, the fixtures, the download script. |
| `node tools/check.mjs` | Loads every GDScript file in a debug run and fails on any warning or error. |
| `node tools/example-events.mjs` | Makes `test/fixtures/*.events.jsonl` again. Run it when `schema/examples/` or the bridge adapters change. A Node test fails when the fixtures are out of date. |
| `node tools/render-art.mjs` | Renders the pictures with the art code in `art/image_src/` in headless Chromium. Needs Playwright, `CHROMIUM_PATH` and the two fonts (`npm install --no-save @fontsource/tiny5@5.3.0 @fontsource/silkscreen@5.3.0` here). Add `--check` to render twice and compare with the files on disk. See "Phase G-2". |
| `"$GODOT" --path . -s res://tools/shot.gd -- --scene=res://src/room.tscn --out=room.png` | Saves the 480x270 viewport of a scene as a PNG file after a few frames. It needs a window (not `--headless`). `--count=5 --frames=600` with `%d` in `--out` saves several pictures. See "Phase G-3". |
| `node tools/record.mjs --scene tour` | Records a scene as a 1920x1080 clip (needs a window and ffmpeg). `--stills 7,22.5` saves stills. `node tools/determinism.mjs` records a scene twice and compares every frame. See "Phase G-8". |
| `node tools/startup.mjs`, `node tools/cost.mjs` | The time to the first frame, and the CPU and memory in each state of the window. They need a window. See "Phase G-6". `cost.mjs` takes `--engine-arg=` (for example `--engine-arg=--audio-driver --engine-arg=Dummy`) and `--client-arg=--sound=krakowiak`: see "Phase G-7". |
| `node tools/sound-levels.mjs` | The levels of each tune with each event sound, from the files in `art/sound/`, and how far the sum goes above full scale. See "Phase G-7". |
| `"$GODOT" --path . -s res://tools/ui_shots.gd -- --out=<folder> --shots="arenas:12:menu,..."` | Stills of the live view in chosen states (a menu, a hover, the overview) in one run. See "Phase G-6". |
| `node tools/benchmark-report.mjs run.csv` | Prints the frame times of the long camera moves of a benchmark run (`"$GODOT" --path . -- --benchmark=ten --benchmark-out=run.csv`, which needs a window). See "Phase G-5". |

What the tests cover:

* `test/test_event.gd`: parses every event of the four example sessions (`schema/examples/`, after the
  bridge adapters mapped them to canonical events). It also checks the rejection of bad messages.
* `test/test_schema.gd`: the category list in `event.gd` equals the enum in `schema/event.schema.json`.
* `test/test_bridge_client.gd`, `test_options.gd`, `test_main.gd`: the client, the options and the text view.
* `tools/bridge-link.test.mjs`: starts the real bridge on a free port and runs the real client headless
  (`tools/link_probe.gd`). It posts events and checks the order (also for a burst of 200 events), and that
  the client reconnects after the bridge restarts. It also checks that a client with no bridge keeps trying.
* `tools/license.test.mjs`: the license split (see below).
* `test/test_arena_rules.gd`, `tools/parity.test.mjs`, `test/test_arena_golden.gd`, `test/test_rng.gd`,
  `test/test_porting_traps.gd`: the arena rules (see "Phase G-1").
* `test/test_s6_stats.gd`: the numbers of spike S-6 (percentiles, fit scale, picture compare).
* `test/test_atlas.gd`, `test_draw_kit.gd`, `test_text_art.gd`, `test_gallery.gd`, `tools/art-render.test.mjs`:
  the pictures, the atlas data and the art code (see "Phase G-2").
* `test/test_stations.gd`, `test_spots.gd`, `test_room_view.gd`: the station table, the spot and queue rules, and the room view (see "Phase G-3").
* `test/test_clock.gd`, `test_director.gd`, `test_penguin_actor.gd`, `test_backlog.gd`, `test_focus.gd`, `test_effects.gd`, `test_timeline_player.gd`,
  `test_behaviour_trace.gd`, `test_penguin_view.gd`, `test_live_view.gd`, `test_frame_policy.gd`, `test_simulation_cost.gd`, and
  `tools/export-scenes.test.mjs` (the scene files: schema, story and what the old mockup drew), `tools/run-gut.test.mjs`: the behaviour layer and the scenes (see "Phase G-4").
* `test/test_log_model.gd`, `test_bar_layout.gd`, `test_interface_model.gd`, `test_ui_input.gd`, `test_interface_art.gd`, `test_scripted_input.gd`,
  `test_startup_report.gd`, `tools/cost.test.mjs`: the log and the cards, the places of the bar, the interface model and its hit tests, the keys
  and clicks, the drawing, the scripted input test, and the numbers of the start-up and cost tools (see "Phase G-6").
* `test/test_sound_model.gd`, `test_sound_cues.gd`, `test_sound_player.gd`, `test_sound_levels.gd`, `test_sound_input.gd`, `tools/sound-levels.test.mjs`: the sound model and its rules, the cues of the actors, the players under the dummy audio driver, the levels and the master limiter, and the keys, clicks and drawing of the switch (see "Phase G-7"). `test_sound_files.gd` (phase S-4) checks the files.
* `test/test_recording.gd`, `test_tour.gd`, `tools/record.test.mjs`, `tools/replay.test.mjs`: recording mode, the tour with its art, the recorder's options, and a replay through the real bridge into the real client (see "Phase G-8").
* `test/test_camera_parity.gd`, `test_director_arenas.gd`, `test_arena_view.gd`, `test_scene_camera.gd`, `tools/benchmark-report.test.mjs`: the
  incremental camera, the arenas in the director, the camera view, the camera of the four scenes against the mockup, and the benchmark
  report (see "Phase G-5").

### GDScript warnings

Typed GDScript is the rule. `project.godot` turns on `untyped_declaration` and the integer-division warning.
Godot 4.7.2 prints GDScript warnings only in a debug run (`-d`), and `--check-only` does not report them.
So `tools/check.mjs` loads all scripts in one debug run and fails on any `WARNING` or `ERROR` line.
The setting `treat_warnings_as_errors` is in `project.godot` too, for the editor, but a plain `load` in a
headless run did not make a warning fatal.

### The license check

`tools/license.test.mjs` checks the split between the MIT code and the art (`LICENSE-ASSETS`):

* each `.gd` file in `godot/art/` starts with the copyright header, and each `.js` file there starts with the same
  lines behind `//`;
* `art/images/` and `art/sound/` hold only image and sound files. `art/MANIFEST.txt` starts with the copyright
  line and lists the SHA-256 hash of each of those files, as `<hash>  <path relative to art/>`.
  It is required when those folders hold files;
* `LICENSE-ASSETS` names `godot/art/`;
* no `.gd` file outside `godot/art/` and `godot/addons/` calls a drawing or sound API
  (`set_pixel`, `fill_rect`, `_draw`, `draw_rect`, `draw_string`, `draw_texture*`, `AudioStreamGenerator`, ...);
* no `.gdshader` file exists, and no image or sound file lies outside `godot/art/` and `godot/addons/`.

It is a heuristic. A person reviews each change near the line.

## Spike results (phase G-0)

Run on 2026-11-15 with Godot 4.7.2 (standard build) on Windows 11, against the bridge in this repository.

**S-1: does `WebSocketPeer` work headless, and does it send an `Origin` header?**

* **Headless: yes.** `godot --headless` connects to `ws://127.0.0.1:<port>/ws`, receives the `hello`
  message and the events, and reads them in order. `tools/bridge-link.test.mjs` checks this, including a
  burst of 200 events and a restart of the bridge.
* **Origin header: none.** A raw HTTP server saw the upgrade request of the client. It had `host`,
  `upgrade`, `connection`, `sec-websocket-key` and `sec-websocket-version`, and no `origin`. A test keeps
  this fact (`the client sends no Origin header`). So the origin checks planned for the bridge do not
  block a native client. This was checked on Windows only.
* **A closed port is slow to fail on Windows.** With no bridge, `WebSocketPeer` stayed in the connecting state
  for about 30 seconds before it reported a closed socket. So "try again every 2 seconds" would not hold alone.
  The client drops a try after 4 seconds (`CONNECT_TIMEOUT_SECONDS`) and starts the next try at once.
  A connection that was open and then lost is tried again after 2 seconds. Linux and macOS were not checked.
* **Desktop app, not headless: yes.** The app, started with a window, connected and listed the events of a replay.
  A screenshot of the viewport was made and looked at by hand. No automated test does this.
* **Web build: not done.** It needs the web export templates, which are a large download. The class reference
  said that some members are not available on the web. This is still open for phase G-9.

**S-2: does GUT run headless with the pinned Godot?**

* **Yes.** GUT 9.7.1 (the branch `godot_4_7`, the same commit as the tag `v9.7.1`) runs with
  `godot --headless -s addons/gut/gut_cmdln.gd` under Godot 4.7.2. It sets the exit code to 1 when a test fails.
  The project must be imported once before the run (`--import`): `tools/run-gut.mjs` does this.
* GdUnit4 was **not tried**, because GUT works.
* JUnit XML output was **not tried**.

## Phase G-1: the arena rules

`src/core/arena_rules.gd` is a faithful, typed port of `tools/mockup-2d/arena-rules.js`. It has the same
behaviour and the same `DEFAULTS`. Every name is the JavaScript name in snake_case (`createArenas` is
`create_arenas`, `simulateCamera` is `simulate_camera`). This first version is a batch port: it reads the
whole script of a session, so it knows when an approval ends (`until`). Phase G-5 makes the camera incremental.

```gdscript
const ArenaRules := preload("res://src/core/arena_rules.gd")
var arenas := ArenaRules.create_arenas({ "arena_size": 4 })   # place(n, now), leave(n, now), tick(now), letters()
var sim := ArenaRules.simulate_camera({ "events": [], "opened": [], "inputs": [], "duration": 30.0 })
sim.log      # Array[Dictionary]: one entry for each move, with t, to and why
sim.frames   # Array[Dictionary]: one frame for each step of 1/30 s
sim.at(2.1)  # the frame nearest to a time
```

`src/core/rng.gd` is `mulberry32` with 32-bit masking: `Rng.mulberry32(seed)`, then `next()` (a float) or
`next_u32()` (an integer).

### Decisions

* **Names.** Two names differ from the plain snake_case form. `ease` is `ease_k`, because `ease` is a built-in
  GDScript function. The field `log` of the camera result keeps its name. A `@warning_ignore` hides the clash
  with the built-in `log` function.
* **Options and specs are Dictionaries with snake_case keys** (`hold_after_move`, `reduced_motion`, `focus_events`).
  `DEFAULTS` is a constant Dictionary. Options merge shallowly, as `{...DEFAULTS, ...opts}` does. A `follow` in the
  options replaces the whole default, and `simulate_camera` then fills the gaps from the default, as the JavaScript does.
* **`null` is `null`, typed as `Variant`.** `place()` and `arena_of()` return a `Variant`: a letter or `null`.
  A frame has `null` for `arena` (overview), `from` (arena view), `ribbon` and `arena_from`.
* **Agent numbers are `int`** in the arena model. The camera accepts any number for `n` and only compares it.
  JSON gives floats, and `5.0 == 5` holds in GDScript. But the Dictionary key `5.0` is not the key `5`, so the
  tests turn the numbers of the arena model into `int`.
* **`Math.round` is `js_round`, not `floor(x + 0.5)`.** `js_round` tests `x - floor(x) >= 0.5`, which is exact. The
  plan's `floor(x + 0.5)` gives 1 for 0.49999999999999994, and `Math.round` gives 0. The rules round only values
  that are not negative. The helper is also right for negative halves (a test checks it).
* **Sorts.** The JavaScript relies on stable sorts in two ways. The events, the focus events and the inputs are sorted
  by time: `CameraSim.sorted_by_t` adds the position as a tie-break. The choice of a pull, of an approval for `N` and
  of an arena for activity is `sort(...)[0]` in the JavaScript. The port scans and keeps the first of equal values,
  which gives the same result. Sorts of arena names and pages have no ties.
* **Integer division.** `name_of` divides by 26.0 and rounds down. `place_of` divides the index by 4 and the slot by
  2 as integers, with `@warning_ignore("integer_division")`, because the index is never negative.
* **`Infinity`** is `INF`: `max_arenas`, an approval with no `until`, and the input `pace`.
* **No lambdas for state.** `CameraSim` keeps all its state in member fields, and its helpers are methods.
  The only lambda is the comparator in `sorted_by_t`, which reads one array.
* **No arena left.** If every arena is closed at once, the JavaScript cuts to `undefined` and goes on with `NaN`.
  The port keeps the view in that case. No scene and no test has it.
* **`CameraSim.step(s)` is public**, so that phase G-5 can build the incremental camera from the same code.

### Porting traps: what was checked

| Trap | Result in Godot 4.7.2 |
|---|---|
| A lambda copies the local variables it uses | **Confirmed.** A lambda that does `counter += 1` does not change the outer `counter`. Godot warns about it (`confusable_capture_reassignment`). An Array is shared: only the variable is copied. A test keeps this fact. |
| `round(-0.5)` | It is -1, and `Math.round(-0.5)` is -0. Use `js_round`. |
| `[1.0] == [1]` | **False.** An Array compares an int and a float by type. The golden data are compared with a helper that treats numbers as numbers (`test/support/golden.gd`). |
| `Array[String] == Array` | True when the items are equal. A typed result can be compared with a plain literal. |
| Integer overflow | A 64-bit product wraps in GDScript. `rng.gd` still builds `Math.imul` from 16-bit parts, so it does not rely on that. |

### The tests

* `test/test_arena_rules.gd` has the 34 cases of `tools/mockup-2d/arena-rules.test.mjs`, in the same order. Above
  each test, `# JS: <title>` holds the exact title of the JavaScript test.
* `tools/parity.test.mjs` reads both files and fails when a JavaScript title has no counterpart. It also fails for
  a title with no JavaScript test, for a different order, and for a comment that is not directly above a test.
* `test/test_arena_golden.gd` runs the specs of `test/fixtures/` through the port and compares with the JavaScript.
  Floats must agree within 1e-9. It covers the pure functions, the arena model, and the camera log and every frame.
* `test/test_rng.gd` compares the first 64 outputs of `mulberry32` for 14 seeds with the JavaScript (as integers).
* `test/test_porting_traps.gd` has one test for each trap that the golden data cannot show.

### Golden data

These files are fixed. No tool makes them. `test/fixtures/README.md` says the same. Do not edit them by hand.

| File | Content |
|---|---|
| `arena_rules.json` | The pure functions (many calls each), 9 scripts of the arena model (4 from the tests, 5 made from seeded random numbers), and 47 camera cases: 29 from the specs of the tests, 12 more for ties, reduced motion, closing and the edges of the keys, and 6 random sessions. |
| `rng.json` | The first 64 outputs of `mulberry32` for 14 seeds. |
| `camera-arenas.json`, `-many`, `-ten`, `-follow` | The camera input that `tools/mockup-2d/arenas.js` builds for each scene (`events`, `focusEvents`, `opened`, `closed`, `inputs`, `opts`), and the log and frames of the JavaScript camera. |

Each file starts with a provenance note: the last commit that changed `tools/mockup-2d`, and the SHA-256 hash of each
mockup file that the data depend on (line ends count as LF). A camera run has a frame for every 1/30 s,
so a frame is stored as the keys that changed since the frame before. Infinity is stored as the string `"Infinity"`.
The files take about 1.8 MB together.

The camera files were made with a browser: a small script wrapped `simulateCamera` in the mockup page and kept its arguments, and the JavaScript rules then ran on them in Node.

## Sound files (spike S-4 and the render tool of phase G-7)

The client plays WAV files. `art/sound/` holds four tunes (one exact loop each) and five event sounds. They are
made at build time by the synthesiser of the mockup. A copy of it lives in `art/sound_src/sound.js`, with its header.
The mockup's own file did not change. Nothing is made at run time. This section is the note of spike S-4.
The Godot player, the sound model and the sound menu are in "Phase G-7" below.

```bash
cd godot
node tools/render-sound.mjs            # renders art/sound/*.wav and writes the sound lines of art/MANIFEST.txt
node tools/render-sound.mjs --check    # renders again, compares with art/sound/ and the manifest, writes nothing
node tools/render-sound.mjs --rate 44100 --out some/folder   # the other rate, into another folder
```

The tool needs Playwright and a Chrome or Chromium (`PLAYWRIGHT_DIR` and `CHROMIUM_PATH`, as for `render-art.mjs`).
A full render takes about one minute. `tools/render-sound.test.mjs` needs no browser. It checks the helpers, the numbers
of the tool against `sound.js`, and the files in `art/sound/`.

### The files

The files in the repository are the 22.05 kHz set (mono, 16 bit). Peak and RMS are in dB below full scale (dBFS).
Each file holds the mix of the mockup: music gain 0.45, effect gain 0.75, and a gentle limiter.

| File | Rate (Hz) | Length (s) | Samples | Peak (dBFS) | RMS (dBFS) | Bytes | Bytes at 44.1 kHz |
|---|---|---|---|---|---|---|---|
| `krakowiak.wav` | 22057 | 55.652 | 1227520 | -4.0 | -20.6 | 2455084 | 4907564 |
| `kujawiak.wav` | 22036 | 68.571 | 1511040 | -5.3 | -21.3 | 3022124 | 6048044 |
| `oberek.wav` | 22048 | 60.000 | 1322880 | -1.8 | -20.7 | 2645804 | 5291564 |
| `goralski.wav` | 22048 | 40.000 | 881920 | -5.6 | -21.8 | 1763884 | 3527724 |
| `tink.wav` | 22050 | 0.125 | 2750 | -21.5 | -33.1 | 5544 | 11048 |
| `bell.wav` | 22050 | 0.924 | 20384 | -8.8 | -19.1 | 40812 | 81584 |
| `flop.wav` | 22050 | 0.605 | 13338 | -3.1 | -20.1 | 26720 | 53400 |
| `chime.wav` | 22050 | 0.645 | 14214 | -8.6 | -21.5 | 28472 | 56896 |
| `fanfare.wav` | 22050 | 1.104 | 24353 | -12.1 | -22.3 | 48750 | 97458 |
| **Total** | | | | | | **10037194** (9.57 MiB) | **20075282** (19.15 MiB) |

The tool fails on silence (RMS below -60 dBFS) and on clipping (a sample at full scale). No file does either.
The highest peak is the oberek at -1.8 dBFS. An event sound starts with no silence: the tool cuts the delay of the
limiter. It ends where the tail is below 4 steps of 16 bits.

### The loop lengths

A tune is an intro, then the melody again and again. The lead's sound alternates between two sounds, one for each pass
of the melody. So one loop is two passes. The number of bars of a pass comes from `sound.js`, and
`render-sound.test.mjs` checks it. The loop does not include the intro.

| Tune | Melody (bars) | Loop (bars) | Metre and tempo | Bar (s) | Loop (s) |
|---|---|---|---|---|---|
| krakowiak | 32 | 64 | 2 beats, 138 a minute | 20/23 = 0.8696 | 1280/23 = 55.652 |
| kujawiak | 16 | 32 | 3 beats, 84 a minute | 15/7 = 2.1429 | 480/7 = 68.571 |
| oberek | 32 | 64 | 3 beats, 192 a minute | 15/16 = 0.9375 | 60 |
| goralski | 20 | 40 | 2 beats, 120 a minute | 1 | 40 |

### How the loop is made, and how it was checked

A note or a release tail can cross the end of a loop, and the limiter keeps a state. So the tool renders the intro and
three loops in one go, and keeps the second loop. The loop then starts with the tails of the loop before it. It ends
where the tails flow into the next loop. A plain cut did not work: the loops differed from each other everywhere
(the difference was about half of the RMS level). Four things had to be solved:

1. **The loop must be a whole number of render blocks.** Chromium renders in blocks of 128 samples. It places a note by
   its place in a block, with a shift of less than one sample. At 22050 Hz the loop of the krakowiak is 1227130.43
   samples long, so each pass puts its notes in other places. The tool moves the sample rate of each tune to the nearest
   whole rate at which the loop is a whole number of blocks (`loopRate`). The change is 0.07% at most (see the table).
   The WAV header holds the real rate, so Godot plays the tune at the right speed and pitch.
2. **The noise hits depend on the absolute time.** `sound.js` starts each hit at `(at * 7.31) % 0.5` in its noise
   buffer. The tool makes this place depend on the time inside the loop. A hit keeps its time, level and filter.
   Only the slice of the seeded noise changes.
3. **A note on a whole sample can move by one sample.** A note time is a sum of doubles. The sum differs by about 1e-13 s
   from pass to pass. When a note falls on a whole sample, it can land on the sample before or after. The tool adds
   0.1234 of a sample (5.6 us) to every time of a tune, so that no note is near a sample boundary.
   Oberek and goralski have exact bar lengths and did not need this. Krakowiak and kujawiak did.
4. **Chromium adds three or more inputs in an order that depends on memory addresses.** The float sum then differs by
   one unit of its last digit from run to run, and a few samples of the 16-bit output change by one step. Two renders
   of the same sound were not equal. The tool lets each node add two inputs at most, with a chain of gain nodes
   (gain 1). The sum of two numbers does not depend on their order (`deterministicSums`). After this, 12 renders of
   each event sound in each of two processes gave one result for each sound.

Changes 2 and 3 apply to the tunes only. The event sounds are rendered as `sound.js` makes them, with change 4.
A comparison with an unchanged render of a tune is not made. A shift of 0.33 sample alone changes a waveform by
about 20% of its RMS, so such a comparison measures phase and not sound.

**What the tool checks for each tune.** It fails when one check fails.

1. The third loop equals the second one. The largest difference of a sample is 0 (krakowiak, oberek, goralski) or 1
   (kujawiak) step of 16 bits. This is the rounding of the render. The RMS of the difference is 0.00, against an RMS
   level of about 2800 to 3000.
2. The join. The last 4096 samples and the first 4096 samples of the file, in the order in which they follow each other
   when the file loops, equal the samples around the same place in the continuous render (where loop 2 goes into loop
   3). The largest difference is 0 for all four tunes.
3. The jump from the last sample to the first sample is not larger than the largest step inside the loop. The jump is 0
   (krakowiak, oberek), 7 (kujawiak) and 10 (goralski) steps. The largest step inside a loop is 2114 to 5844 steps.
   The mean step is 270 to 422.
4. The loop is not a repeat of a shorter loop. The loop shifted by 1/2, 1/3, 1/4, 1/5 or 1/6 of its length is not equal
   to itself.

`test/test_sound_files.gd` checks the last and the first sample again in the loaded Godot resource (a jump of 50 steps
at most). It plays nothing. Whether the join *sounds* right was not checked (see the end of this section).

### The same bytes on every run

Two separate runs of `render-sound.mjs` gave the same bytes for all nine files (`cmp` on each file).
`node tools/render-sound.mjs --check` does the same against the files in `art/sound/` and the manifest.
Before change 4, two runs differed in 1 to 120 samples of each file, by one step each. Another version of Chromium may
still give other bytes. The hashes in `art/MANIFEST.txt` are those of the committed files.
Render rarely. A new render adds the whole size of the files to the history of git.

### Sample rate and size: the proposal

The budget in the plan is 10 MB for all files.

| Rate | Total | Against the budget |
|---|---|---|
| 44.1 kHz | 20075282 bytes (19.15 MiB) | Twice the budget |
| 22.05 kHz | 10037194 bytes (9.57 MiB) | 0.4% over 10 MB (decimal), under 10 MiB |

**Proposal: 22.05 kHz.** It halves the size. The plan guessed that chiptune sound may not need more. The owner decides.

The comparison used the average power spectrum of each file (Hann window; 4096 points at 44.1 kHz and 2048 points at
22.05 kHz, so a bin is 10.8 Hz wide). Below 4 kHz the two renders have the same share of the energy, within 0.2 dB.
Above that the 22.05 kHz files lose a little:

| Band | Share of the energy of a tune at 44.1 kHz | The 22.05 kHz file, against it |
|---|---|---|
| 4 to 6 kHz | -24 to -39 dB | 0.4 to 1.1 dB lower (fanfare: 2.2 dB) |
| 6 to 8 kHz | -32 to -45 dB | 0.7 to 4.6 dB lower |
| 8 to 11 kHz | -40 to -49 dB | 8 to 16 dB lower |
| 11 to 22 kHz | -45 to -52 dB | lost (the file stops at 11 kHz) |

The shares are against the total energy of the file. What is reduced by more than 1 dB or lost is at least 32 dB below
that total. It is the top of the buzz of the square waves. The levels are almost the same: the RMS of a file differs by
0.4 dB at most between the two rates, and the peak by 0.7 dB at most.

**What I cannot judge:** how the two sets sound, because I cannot listen. A person must compare them. The high notes
of the fanfare and the bright lead of the goralski are the places to listen to. Also not judged: the resampling in
Godot. It plays a 22.05 kHz file at the mix rate of the output (often 44.1 or 48 kHz). It may add a little noise above 11 kHz.

### The import in Godot 4.7.2

Each file has a `.import` file next to it. Godot makes it, and these settings were changed:

| Setting | Tunes | Event sounds |
|---|---|---|
| `edit/loop_mode` | 2 (forward) | 1 (disabled) |
| `edit/loop_begin` | 0 | 0 |
| `edit/loop_end` | the number of samples of the file | -1 (not used) |
| `compress/mode` | 0 (PCM, not compressed) | 0 |

* The default `compress/mode` of Godot 4.7.2 is 2 (QOA, a lossy format). It is not used, so that the loop stays exact.
  The cost is memory: Godot keeps the PCM data, so the four tunes take 9.9 MB when all are loaded. QOA may be worth a
  test later, with a listening check and a check of the join.
* **`loop_end` must be the number of samples.** With `-1`, Godot 4.7.2 sets the end one sample before the end of the
  file. The test found 1227519 for a file of 1227520 samples. After a new render, set `loop_end` again in the `.import`
  file of each tune (the report of the tool has the number). `test_sound_files.gd` fails when it is wrong.
* The files have odd rates (22057, 22036, 22048). Godot accepts any rate. A run with sound was not made.

`test/test_sound_files.gd` loads every file with `load()`. It checks these things:

* a stream exists;
* the length (for a tune, the loop length of the table above, within 1 ms);
* the format (16 bit, mono, near 22050 Hz, not compressed);
* the loop mode, the loop begin and the loop end;
* the join, and that no sample is at full scale.

It reads the properties with `get()` and does not name the stream class. So the license check needs no change:
`AudioStreamWAV` is a forbidden word outside `art/`. The test makes no sound. It only loads and reads.

### What was checked, and what was not

* Checked: nine files, rendered twice, with the same bytes. The loop checks pass for all four tunes.
  `cd godot && npm test` passes (86 GUT tests and 43 Node tests). `node tools/check.mjs` and the license check pass.
  The mockup, the schema and the bridge did not change.
* Not checked: how anything sounds (the tunes, the join of a loop, 22.05 kHz against 44.1 kHz). Playing a file in Godot.
  A render on another machine, with another Chromium, or on macOS or Linux (a Windows machine with Chrome was used).
  The effect of the limiter when a tune and an event sound play together (each file has its own limiter).

## Phase G-2: art as files

The pictures of the client are PNG files. `tools/render-art.mjs` makes them with the art code of the mockup. The
client only loads them. The tool runs `art/image_src/look.js` (made as a copy of the mockup's `look.js`; the only copy now)
in headless Chromium, packs the pictures in a fixed order, and writes the PNG files itself.

```bash
cd godot
npm install --no-save playwright @fontsource/tiny5@5.3.0 @fontsource/silkscreen@5.3.0   # here, or set PLAYWRIGHT_DIR and FONTSOURCE_DIR. Not in a package.json.
export CHROMIUM_PATH=/path/to/chrome            # a Chrome or Chromium that you have
node tools/render-art.mjs                       # writes art/images/*.png, art/atlas_data.gd, art/MANIFEST.txt (its images/ lines),
                                                #   test/fixtures/art_variants.json
node tools/render-art.mjs --check               # renders twice, compares the two runs and the files on disk, writes nothing
```

### What is in `art/`

| File | Content |
|---|---|
| `image_src/look.js` | The art code of the old mockup (`art/look.js`), moved here. It is the only copy. |
| `image_src/base.js`, `effects_src.js` | Copies of what `look.js` needs from `base.js`, and of the cloud and the candle from `session-art.js`. |
| `image_src/variants.js` | The variant table: every picture that the client may ask for (see below). |
| `image_src/bake.js` | Runs in the baker page. It calls `look.js` for each entry of the table and checks the output. |
| `images/*.png` | 13 files, 88 KB in all: five penguin sheets (one for each cord colour), `props.png`, `effects.png`, `glyphs.png`, and five rooms. |
| `atlas_data.gd` | Generated. The name and the rectangle of each of the 763 pictures, the cord colours, the rugs, the prop places, the animations. |
| `atlas.gd` | Finds a picture by name and draws it (`draw`, `draw_at`, optional mirror and tint). Loads the sheets. |
| `draw_kit.gd` | The primitives of the frame code: `px`, `fill`, `box`, `ellipse` (one rectangle for each row), `line`, `bitmap`, `icon`. |
| `text_art.gd` | Text from the glyph atlas: `width`, `draw`, `rich` (the "✗" is a bitmap, as in the mockup). |
| `room_art.gd` | The room with its sign. The sign is drawn here (see below). |
| `gallery_art.gd` | The pages of the gallery. |
| `MANIFEST.txt` | The SHA-256 hash of each file in `images/`. The render tool changes only the `images/` lines, so the sound lines of phase G-7 stay. |

`draw_kit.gd` has pure functions for the shapes (`ellipse_rects`, `line_points`, `bitmap_rects`, `box_rects`). The tests compare
them with the output of `pxEll`, `pxLine`, `bitmap` and `box` of `look.js`, which ran against a canvas that records each call.

### The variant table

`image_src/variants.js` lists the pictures. The tool writes the list of names to `test/fixtures/art_variants.json`.
The tests read it, and `atlas_data.gd` must hold exactly these names.

| Kind | Names | Count |
|---|---|---|
| Penguin | `penguin/<cord>/<dir>/<pose>`, with `/blink` (eyes closed), `/small` (the helper, scale 0.72) or `/nocap`. `<dir>` is `front`, `side` or `back`. | 74 for each cord, 5 cords |
| Flop pieces | `penguin/<cord>/flop-body` and `penguin/<cord>/cap` (cropped, as `drawAt` uses them) | 2 for each cord (in the 74) |
| Props | The 12 pictures of the room table of the mockup, a plant, a pegboard, a cloud, and a candle of each length 3 to 8. `PROP_PLACES` has the depth, the centre and the bottom of each. | 21 |
| Effects | `icon/<category>` (the ten 7x7 icons), `spark/0` to `spark/3`, `spark/mini`, `flame/0` to `flame/3` | 19 |
| Rooms | `room/<rug>` for `red`, `cobalt`, `emerald`, `yellow`, `teal` (480x232) | 5 |
| Glyphs | `glyph/<font>/U+XXXX` for the fonts `tiny5-8`, `silk-8` and `silk-16` | 116 for each font |

* **Left is not baked.** The left view of a penguin is the right view, mirrored (`Atlas.draw(..., flip_h = true)`). The gallery has a page that shows this.
* **Cord colours** are the four of `CORDS` of the old mockup and a grey `default` for an unknown framework. The grey is a choice of this phase (see "Open questions").
* **Poses** come from the flipper switch and the side table of `penguin(o)`, and from the poses that the scenes use. `ANIMATIONS` lists the frames of each activity as the mockup plays them (walk, read, hammer, shovel, tap, wave, cheer, ...), so the actor of phase G-4 can name them. A test checks that every frame exists for every cord.
* **Rooms.** `room()` draws the sign with `text()`. The letter of an arena changes, so the baked room has an empty sign board, and `room_art.gd` draws the text and the plate with the same arithmetic. The baker draws the full room as well, and **fails** if the baked room plus the sign is not the same picture, pixel for pixel. It checks 14 signs for each rug (the single room, single letters of every width, and double letters). A GUT test compares the layout in GDScript with the numbers of the browser.
* The effects that depend on time (dust, sparks, smoke, confetti, the candle's flicker) are not baked. Phase G-4 draws them with `draw_kit.gd`.

A new picture: add it to `variants.js`, run `render-art.mjs`, commit the files. Each render changes the PNG files in git, so render when the table changes.

### Same on every run

The browser gives only pixels. The tool encodes the PNG files itself (fixed filter, fixed compression level). `--check` renders twice in one run, and the test
`tools/art-render.test.mjs` does it again and compares the pixels with the files. Checked: two runs in one process, and a run in a new process, gave the same bytes.

Limits:
* The bytes depend on the zlib of Node. Another Node version can give other bytes for the same pixels. The manifest then fails, and the pixels are still the same.
* **`glyphs.png` depends on the browser's text rasterizer.** `look.js` draws text with `fillText`, and the edges of letters are anti-aliased. Everything else (penguins, props, effects, rooms) is made with `fillRect` and gives the same pixels in every browser. The glyph file was made with Chrome on Windows. See spike S-3 for what this changes.

### Import settings

Godot imported the PNG files with these settings, and the `.import` files are committed: lossless (`compress/mode=0`), no mipmaps (`mipmaps/generate=false`).
The filter is nearest: it is the project default (`textures/canvas_textures/default_texture_filter=0`). `test/test_atlas.gd` checks the `.import` files and the project setting.
`process/fix_alpha_border` stays on (the default). **Changed in phase G-5:** the five room PNGs have `mipmaps/generate=true` (spike S-6: a room that is scaled down needs trilinear filtering). The other sheets have none. `test_atlas.gd` says so.

### The gallery

```bash
"$GODOT" --path . res://src/gallery.tscn          # in godot/. Left and right arrow keys change the page.
"$GODOT" --path . res://src/gallery.tscn -- --page=12
```

It has 23 pages: the penguins of each cord (two pages each), the props, the icons, sparks and flames, the mirrored side views, a page for each font, and the rooms with their signs (the single room, arenas A to E, and "AA").
Every page has a line of text with Polish letters. `test/test_gallery.gd` checks that every picture is on a page. A screenshot of 11 of the 23 pages was looked at by hand (penguins of two cords, the props, the icons, the mirrored views, two glyph pages, and three rooms with their signs). They look right. The other pages were not looked at.
The gallery has no automated screenshot check.

### Load time

Measured on 2026-11-15 with Godot 4.7.2 on Windows 11, with an NVIDIA laptop GPU. It is **not** the reference machine of the plan (a low-end laptop with 8 GB). The numbers show that the cost is small.
`"$GODOT" --headless --path godot -s res://tools/load_probe.gd` prints the headless numbers, and `test_atlas.gd` prints a load time too. The gallery prints the time with the upload.

| What | Time |
|---|---|
| The script `atlas_data.gd` (763 pictures), headless, 5 runs | 26 to 33 ms |
| All 13 sheets, headless, no GPU upload, 5 runs | 33 to 37 ms |
| All 13 sheets in the gallery (OpenGL window, with the upload), 5 runs | 36 to 64 ms |
| Memory of the decoded sheets | 6.5 MB (RGBA) |

The budget for the first frame is 2 s. The atlases take about 5% of it on this machine. Each sheet loads in 3 to 5 ms. The five rooms are the largest part of the memory (2.2 MB of the 6.5 MB).

## Spike S-3: the text path

**Question.** Which text path: the glyph atlas that is baked with the mockup's own text routine (the plan's default), or a Godot font? Does the atlas cover the characters that targets use? What do the font licenses say?

**Result. The glyph atlas works as the text path. The Godot font path was not tried.**

* **How it is made.** `bake.js` calls `text()` of `look.js` once for each character, in white. A glyph cell is as wide as the advance of the character and as high as the highest and lowest ink of its font. `text_art.gd` puts the cells side by side and tints them. The three fonts are Tiny5 at 8 px, Silkscreen at 8 px and Silkscreen at 16 px: the sizes that the mockup uses.
* **ASCII and Tiny5 are exact.** For every printable ASCII text that was tried (and for all texts in Tiny5, Polish letters too), the width that `text_art.gd` gives equals `textW()` of the mockup. A GUT test checks 117 texts. The baker also checks that every pixel of the glyph cells is a pixel of the output of `text()`.
* **Characters in the atlas, for each font (116):** printable ASCII (U+0020 to U+007E), the 18 Polish letters (`ĄĆĘŁŃÓŚŹŻąćęłńóśźż`), the middle dot `·` (the bar of the mockup uses it), and the arrows `↑` and `↓`. The mockup also shows `ó` (a name in the sound menu). `✗` is not a glyph: `look.js` draws it as a bitmap, and `text_art.gd` `rich()` does the same. `←` and `→` are not in the latin subset of the fonts, and no scene uses them: they are not in the atlas.
* **Any other character shows as `?`**, drawn in the same font and the same width (a GUT test covers this: Cyrillic, a Chinese character, an arrow, a control character, an emoji).
* **The mockup does not show the Polish letters correctly.** `arena2d.html` loads only the latin subset of the fonts, which has `ó` but not `ąćęłńśźż`. The baker loads the latin-ext subset too, so the atlas has the true glyphs.
* **Polish letters in Silkscreen at 8 px are hard to read.** The accents fill the small cell. Tiny5 is clear. Use Silkscreen only for upper-case titles, or accept this.
* **Known deviations.**
  1. Some Polish letters of Silkscreen have a fractional advance in the font. `textW()` rounds the width of a whole string up, and the atlas rounds each glyph up, so Polish text in Silkscreen can be up to 5 px wider than in the mockup (a test keeps this limit). The pixels of these strings also differ in places.
  2. One column of the large `Ą` (Silkscreen 16 px) lies outside its cell and is cut.
  3. **The rasterizer.** The mockup draws a whole string with one `fillText`. On Chrome for Windows, the light edges of two neighbour letters add up and make ink in the gap between them (1,439 pixels in the 117 test texts). Single glyphs do not have this. The preview images of the mockup show clean gaps, as the atlas has. So the atlas looks like the previews, but it is not identical to a whole string drawn on this machine. The glyph cells depend on the rasterizer of the browser: render the official `glyphs.png` in one fixed environment (the container of phase G-8).
* **What a bitmap atlas gives:** no anti-aliasing or hinting to set in Godot, the same look on every platform, no font files in the app, and text that is cheap to draw (one texture, one rectangle for each character). **What it costs:** a fixed character set, and the license question below.

### The font licenses: what they say (not a decision)

Tiny5 (copyright "The Tiny5 Project Authors") and Silkscreen (copyright "The Silkscreen Project Authors") are both under the SIL Open Font License 1.1. The text is in the `LICENSE` file of each npm package (`@fontsource/tiny5` and `@fontsource/silkscreen`, version 5.3.0). The files show no "Reserved Font Name" after the copyright line. These are the parts that matter for a bitmap made from the fonts:

* "Modified Version" means a derivative made by adding to, deleting or substituting parts of the Font Software, **or by changing formats or by porting the Font Software to a new environment**.
* The Font Software may be used, copied, embedded, modified and redistributed free of charge, but it **may not be sold by itself** (condition 1).
* A copy that is bundled or redistributed with software must carry the copyright notice and the license, as a text file, a header, or metadata (condition 2).
* A Modified Version may not use a Reserved Font Name without permission (condition 3), and may not use the names of the authors to promote it (condition 4).
* The Font Software, **modified or unmodified, in part or in whole, must be distributed entirely under the OFL and not under another license**. "The requirement for fonts to remain under this license does not apply to any document created using the Font Software" (condition 5, and the preamble).
* The license ends if a condition is not met.

What this leaves open: is a PNG atlas of glyphs a derivative of the fonts (a bitmap font, "porting to a new environment"), or is it a rendered document? If it is a derivative, condition 5 asks for the atlas to be OFL, which conflicts with "all rights reserved" for `godot/art/` in `LICENSE-ASSETS`, and condition 2 asks for the notices to ship with it. `LICENSE-ASSETS` today says that the fonts "are not part of these files". The OFL FAQ was not read in this session. This is for the project owner to decide (open question 1).

## Open questions (phase G-2)

1. **The OFL terms for `glyphs.png`** (see above). Decide whether the atlas is a derivative of the fonts. If yes: license the atlas under the OFL with the notices, or use Godot fonts, or draw a font of our own. This also changes the line about the fonts in `LICENSE-ASSETS`. The plan's question 4 asks the same. Nothing was changed in `LICENSE-ASSETS`: it already names `godot/art/`.
2. **Where the fonts come from.** The baker finds them in `FONTSOURCE_DIR` or in `godot/node_modules/`. The proposal: add `@fontsource/tiny5` and `@fontsource/silkscreen` (version 5.3.0) as `devDependencies` of `godot/package.json` and a lock file. This was not done here, because it changes the package files.
3. **The grey cord for an unknown framework** (`#9aa6b5`, the grey of the palette). It is my choice. The mockup has no such cord.
4. **Which environment renders the official `glyphs.png`.** It depends on the browser's text rasterizer (see S-3). The proposal: the container of phase G-8, and a note of its image version in this README.
5. **Polish in Silkscreen.** Accept the deviations, or use Tiny5 for text that can hold Polish letters.
6. **App icons** are not made. The plan puts them in `images/`, but the G-2 row does not name them, and the formats (`.ico`, `.icns`) are open question 4 of the plan.
7. **Poses the actor may still need.** The table starts from the poses of the mockup. Phase G-4 may add some (for example a front `hammer` or a back `read`). Each addition is one line in `variants.js` and one render.

## Phase G-3: room and stations

One room, as the mockup draws it, with a penguin at each of the nine stations. The pictures only: no movement, no
events (phase G-4).

```bash
"$GODOT" --path . res://src/room.tscn            # in godot/. Options after "--": --rug=cobalt, --arena=B, --no-penguins
"$GODOT" --path . -s res://tools/shot.gd -- --scene=res://src/room.tscn --out=room.png    # a PNG of the viewport
```

### What was added

| File | Content |
|---|---|
| `src/core/stations.gd` | The station table. One entry for each category of the schema, in the order of `event.gd`. Each entry has its prop, its spots (a point, the animation of the penguin, the first frame, the shadow) and its queue. `for_category()` gives the entry. An unknown category gives "other", as in `event.gd`. No tool name is used. |
| `src/core/spots.gd` | Spots and the queue. Live logic with no nodes and no clock: `arrive(agent, category)`, `leave(agent)`, `placement_of(agent)`. |
| `art/room_stage_art.gd` | A `Node2D` that draws one room: the baked room and its sign, the glow of the forge and the lamp, then the props and penguins in the order of their depth (the y of the foot), with a shadow under each penguin. It gets the penguins as data. It is art, so it lives in `art/` and has the header. |
| `src/view/room_view.gd`, `src/room.tscn` | The room view. It lets `spots.gd` place one penguin at each station and gives the result to the art node. |
| `tools/shot.gd` | Saves the 480x270 viewport of any scene as a PNG file. |

### The stand points: pixels, and how they relate to the metre table

The stand points are the `PTS` of the JavaScript mockup in room pixels. The room picture is 480x232 pixels, and the
bar of the interface will use the 38 rows below it. The points are the reference for the look. `stations.gd` has them
under the same names (`map`, `shelf`, `benchL`, `benchR`, `forge`, `forge2`, `seat`, `chairFront`, `desk`, `sign`, `scope`,
`odd`, `spotA`, `spotB`, `forgeQ`, `signQ`, ...). A GUT test compares every point with a copy of that table.

The client plan also has a station table in metres. `stations.gd` keeps it (`FLOOR_METRES`) and a small `project()` with the
numbers of the 2D view plan (screen x = 240 + 28 x, screen y = 138 - 11 z). **The pixel points win. No code derives a stand
point from the metres.** The two tables do not agree exactly. The test prints the distance from the projected metre point to the
nearest pixel spot of its station, and fails above 45 px (about 1.6 m):

| Station | Projected metre point | Nearest spot | Distance (px) |
|---|---|---|---|
| read | (44, 105) | shelf (66, 126) | 30.4 |
| search | (128, 72) | map (96, 86) | 34.9 |
| write | (240, 61) | benchL (222, 98) | 41.1 |
| exec | (380, 83) | forge (366, 93) | 17.2 |
| web | (436, 138) | scope (422, 158) | 24.4 |
| delegate | (380, 193) | desk (350, 208) | 33.5 |
| think | (100, 193) | seat (90, 201) | 12.8 |
| ask_permission | (240, 215) | sign (236, 216) | 4.1 |
| other | (44, 160) | odd (74, 160) | 30.0 |

Why keep `project()` at all: the actor of phase G-4, or a later 3D view, may start from floor positions. It is a few lines and it
has tests. If nobody uses it, remove it with `FLOOR_METRES`. The mockup's points were tuned by eye on the
picture, and the metre table came from a rule ("2.2 m in front of the prop"). That is why they differ.

### Spots and the queue (`spots.gd`)

The three rules of the 2D view plan, "Several agents", item 3:

1. **A penguin takes the first free spot.** The spots of a station have an order. The write station has `benchL`, then
   `benchR`. The forge has `forge` (shovel), then `forge2` (hammer, seen from behind). Thinking has the armchair `seat` first,
   then `spotA` and `spotB`. The telescope, the helper desk, the bookshelf, the map table, the sign post and the odd jobs have
   one spot.
2. **A full station gives a queue.** The penguin gets a place in the line. The place is the queue point of the station plus a
   step of 16 px for each penguin before it.
3. **A spot is freed when its penguin leaves.** The first penguin in the line takes the spot that was freed, and the penguins
   behind it move up one place. `leave()` returns the placements that changed, so that the actor of phase G-4 can send each
   penguin to its new place.

A placement is a Dictionary: `agent`, `category`, `station`, `queued`, `spot` (an index, or -1 in the line), `line` (the place in
the line, or -1), `at` (a point name), `point`, `anim`, `frame`, `shadow`. An agent is a number or a string. An agent that arrives
at its own station again keeps its place. An agent that arrives at another station frees its old spot.

**Choices that are mine, not the mockup's** (the owner may want to look at them):

* **Seven queue points are new.** The mockup has a queue only at the forge (`forgeQ`) and at the sign post (`signQ`). The
  other seven stations got a waiting place on free floor beside them: `readQ`, `mapQ`, `benchQ`, `scopeQ`, `deskQ`,
  `thinkQ`, `oddQ` (`CHOSEN_POINTS` in `stations.gd`). A test checks that none of them is in the mockup and that no place is
  closer than 16 px to another. None is drawn yet.
* **A queue for thinking.** The 2D view plan says that a penguin that thinks while the armchair is taken thinks where it stands.
  The mockup scripts give two such places (`spotA`, `spotB`), so the table has them as spots 2 and 3 of the thinking station.
  A fourth thinker waits in the line at `thinkQ`. The director of phase G-4 may decide to let a thinker stand anywhere.
* **The helper does not take a spot.** The helper (the small penguin) stands at `scope` in the mockup, beside a penguin that
  uses the telescope. It is not a station user, so `spots.gd` does not know it.
* **The bench spot `benchR` starts on frame 1** (`hammer2`), as the mockup script reverses the two hammer frames there.
* **A station comes from the category, not from the tool.** `Stations.for_category("something-new")` is the odd jobs. `event.gd`
  already turns an unknown category into "other".

### The room view

`room_stage_art.gd` follows `drawRoom` of the mockup (`crowd-art.js`). A penguin picture is 48 pixels wide and its foot is 46
pixels below its top, so it is drawn at (x - 24, y - 46). The shadow has radius 8 and height 2.4 under the foot, and the seated
penguin has none. Props are placed by their centre x and bottom y (`PROP_PLACES`). Equal depths keep the order in which the
things were added, props first. The mockup's sort is stable and `sort_custom` in GDScript is not, so the sort has a tie-break.
The seated penguin (y 201) lies between the chair back (190) and the chair front (208). The mark on the sign post is drawn with
the prop. The glow of the forge and the lamp is the mockup's, at time 0: the node has a `time` field, and the flicker of the forge
glow is `0.05 + 0.015 sin(9 t)`. All penguins wear the cap cord of `claude-code`.

The view uses the project settings: a 480x270 viewport, integer scaling and the nearest filter. The room is 480x232. The 38 rows
below it show the clear colour of the log background. The bar of the interface is phase G-6.

### Comparison with the mockup (looked at by hand)

I made mockup stills of the default scene (`record.mjs --stills 0,2.9,3,4.2,6.6,10,12,13.2,14,19.5,22.1,23,26`, and three for
`multi`). I put them next to screenshots of the room view, with a pixel difference of the room (480x232). I looked at the pictures myself.

* **The empty room.** The room view without penguins (`--no-penguins`) against the mockup at t = 0: 204 pixels differ. They are
  the sound switch in the top right corner (interface, phase G-6) and the random fire pixels that the mockup draws at the forge in
  each frame (`forgeLife`, phase G-4). The room, the sign "AGENT WORKSHOP", the glow, the 12 props, the "?" on the sign post, the door
  mat and the wall are the same pixels.
* **Penguins.** At the map table, the bookshelf, the armchair, the workbench, the helper desk, the forge and the sign post, the
  penguin of the room view has the same size, direction and place as the mockup's penguin on the same spot, in the first frame
  of its animation. The mockup shows another frame of the animation at the time of its still. The shadow is the same. The
  penguin in the armchair sits between the chair back and the chair front. I did **not** compare the telescope penguin (full size),
  the odd jobs penguin and the second spots (`benchR`, `forge2`, `spotA`, `spotB`) with a still of the mockup, because the
  default scene never puts a full-size penguin there. They use the same coordinates (a test checks them against the table of the mockup),
  and the pictures look right.
* **Differences that are not mistakes:**
  1. The default scene of the mockup has the workbench penguin at x = 240 (`PT.bench` in `session.js`). The room view uses
     `benchL` = 222 from `crowd.js`, as the task says. The multi-agent scenes use 222 and 258.
  2. The room view has no tags above the heads, no number chips, no focus ring, no notice at the sign post, no cloud and candle,
     no bar, no log, no sparks or dust and no sound switch. These are the interface (G-6) and the effects (G-4).
  3. There is no helper. The default scene of the mockup shows a small penguin at the telescope.
* **A mistake found, from phase G-2 (fixed).** `Atlas.draw` moved a mirrored picture one width to the right. The mirror page of
  the gallery did not show it, because it draws each picture in its own cell. In the room view, the bookshelf and odd jobs
  penguins stood 48 px too far right, in the open floor. A negative width in `draw_texture_rect_region` mirrors in place in
  Godot 4.7.2. `Atlas.destination()` now gives the rectangle, and `test_atlas.gd` keeps it. I checked the effect on a screenshot
  only: no headless test can show the pixels.

### What was checked, and what was not

* Checked: the GUT tests (164 in all, 42 new), `node --test` in `godot/` (57 pass, 1 skipped), `node tools/check.mjs` (no warnings)
  and `npm test` of the mockup (38 pass). The screenshots and the pixel difference above.
* Not checked: a run on another machine or system. The room view in a window of another size: the project scales by whole numbers,
  and I looked at the 480x270 viewport, not at the scaled window. The speed of the room view (it draws a few hundred small
  rectangles in each frame, and I measured nothing). A picture of the full crowd on the second spots.
* The look rules (rule 4 of `CLAUDE.md`, from ADR 0004): the room view shows only the art of the mockup. It has no logo, no
  mascot, no asterisk spinner, no terminal layout and no other typeface. I checked the rules in `CLAUDE.md`, and I did not
  read the ADR itself.
* A GUT script with a parse error is not run, and the run still ends with "All tests passed". GUT only prints a warning
  (`Ignoring script ... because it does not extend GutTest`). It happened to `test_spots.gd` while I wrote it. Look at the number of
  scripts in the summary (17 now). `tools/run-gut.mjs` could fail on that warning.

### Open questions (phase G-3)

1. **The metre table.** Keep `FLOOR_METRES` and `project()`, or remove them now? Nothing uses them, and the pixel points win. The
   plan asks for a projection in the G-3 row, so I kept it small and tested.
2. **The seven new queue points.** Are the waiting places beside the stations acceptable, or should the mockup get queue
   points for all stations first?
3. **Thinkers beyond the armchair.** Stand on `spotA` and `spotB`, as the mockup scripts do, and then wait in a line? Or think
   where they stand, as the 2D view plan says?
4. **A test for GUT scripts that do not load.** `tools/run-gut.mjs` should fail when GUT ignores a script (see above).
   I did not change it, because it is outside this phase.

## Spike S-6: one SubViewport per room, or one world with filtered textures

**Question.** What does one `SubViewport` per room cost with about 16 rooms in view, against one world with filtered textures? And which way gives the right picture when a room is scaled down?

**Answer in short.** Use one shared world (way B) with a mipmapped room texture. On this machine with 16 rooms it is 1.4 to 2.3 times cheaper than a `SubViewport` for each room, and it is the only way that shows a correct picture below scale 0.5. Both ways are fast enough here: no 99th percentile frame is above 6 ms. See "Recommendation for G-5" at the end of this section.

### The machine

| Part | Value |
|---|---|
| CPU | 11th Gen Intel Core i7-11800H, 2.3 GHz (8 cores) |
| GPU | NVIDIA GeForce RTX 3060 Laptop GPU. It is a **discrete** GPU. The OpenGL renderer of Godot reports the type as "other", so the type comes from the model |
| Driver and renderer | OpenGL 3.3 (NVIDIA driver 621.14), Godot 4.7.2 Compatibility |
| OS | Windows 11 |
| Screen | 1920x1080, **360 Hz** (`DisplayServer.screen_get_refresh_rate()`) |
| Window | 1440x810 (the project setting), viewport 480x270 |

This is **not** the reference machine of the plan (a low-end laptop with 8 GB). It is much faster. The numbers show how the two ways compare. They do not show that the budget holds on the reference machine.

### What was built

The code is in `spikes/s6/`. The art code that the license check keeps in `art/` is in `art/s6_support.gd` (see "Rules that got in the way").

| File | Content |
|---|---|
| `spikes/s6/s6_room.gd` | One room made of sprites only: the baked room and its sign (from `art/room_art.gd`), the 12 props, four penguins that walk (with the real walk frames), two flames, four sparks and one icon bubble. About 25 sprites. Positions change every frame. Sprites sort by `y_sort_enabled` inside the room. |
| `spikes/s6/s6_world.gd` | N rooms in a grid (480x232 each, gutter 16). It builds the rooms in one of six ways and sets the scale of the whole grid. The scale of this node is the camera. |
| `spikes/s6/s6_runner.gd`, `s6_runner.tscn` | The runner: plays each case, writes `results.csv`, and takes the pictures. |
| `spikes/s6/s6_stats.gd` | Percentiles, the summary of a run, the fit scale, the picture compare. Tested in `test/test_s6_stats.gd`. |
| `spikes/s6/data/results.csv` | The numbers of all 180 runs. |
| `art/s6_support.gd` | A node that draws the room and its sign. A function that makes a copy of a sheet texture with mipmaps. |

The six ways:

| Way | What it is |
|---|---|
| `A-always` | A `SubViewport` of 480x232 for each room (nearest filter inside). A sprite shows its texture with linear filtering. Update mode `UPDATE_ALWAYS`. |
| `A-visible` | The same, with `UPDATE_WHEN_VISIBLE`. |
| `B-mips` | One world. The room texture has mipmaps and uses trilinear filtering. The sprites use linear filtering (their sheets have no mipmaps). |
| `B-linear` | One world. Linear filtering for everything. No mipmaps. |
| `B-nearest` | One world. Nearest filtering for everything. This is the plain way. It shows the cost floor and the problem. |
| `B-allmips` | One world. Mipmaps and trilinear filtering for the room and for all sprite sheets. |

Cases: 1, 4, 9 and 16 rooms, each at scale 1, scale 0.5, "fit" and "zoom". "Fit" is the scale at which the whole grid fits the 480x270 view: 0.49, 0.33 and 0.24 for 4, 9 and 16 rooms (not run for one room). "Zoom" is a smooth zoom from 1 to the fit scale (to 0.5 for one room) and back, one round trip in 4 s. Every case ran for 1 s of warm-up and 10 s of measurement, with vsync off and with vsync on: 180 runs.

**At scale 1 and 0.5 not all rooms are in view.** The column "In view" in the tables gives the number of rooms that touch the view (a range during a zoom). This is how a camera sees the grid. The renderer culls rooms out of view for sprites (way B). It does not stop a `SubViewport` set to `UPDATE_ALWAYS`.

The frame time is the time between two calls of `_process` (`Time.get_ticks_usec()`). It includes the wait for vsync. Each room moves with fixed random numbers (a seed for each room), so every way draws the same story.

```bash
cd godot
"$GODOT" --path . res://spikes/s6/s6_runner.tscn -- --s6-out=spikes/s6/data/results.csv   # all 180 runs, about 33 minutes
"$GODOT" --path . res://spikes/s6/s6_runner.tscn -- --s6-shots=/some/folder         # the pictures and their numbers
```

The runner needs a window and a GPU (not `--headless`). The options are in the head of `s6_runner.gd`. The columns of `results.csv` are: frames, mean, median, 95th and 99th percentile and worst frame time in ms, the share of frames over 16.7 ms, process time (`TIME_PROCESS`), draw calls, rooms in view, memory.

### Frame times

All numbers are in milliseconds. The first tables show the median and the 99th percentile (p99), then the worst frame. The 95th percentile and the other columns are in `results.csv`. No run had more than 0.07% of its frames over 16.7 ms.

**vsync off: median / 99th percentile (ms)**

| Rooms | Scale | In view | A-always | A-visible | B-mips | B-linear | B-nearest | B-allmips |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 0.66 / 1.32 | 0.76 / 1.50 | 0.82 / 1.64 | 0.74 / 1.38 | 0.72 / 1.25 | 0.75 / 1.40 |
| 1 | 0.5 | 1 | 0.69 / 1.43 | 0.77 / 1.42 | 0.88 / 2.08 | 0.78 / 1.88 | 0.77 / 1.57 | 0.78 / 1.38 |
| 1 | zoom | 1 | 0.72 / 1.41 | 0.80 / 1.46 | 0.76 / 1.66 | 0.74 / 1.41 | 0.76 / 1.44 | 0.78 / 1.34 |
| 4 | 1 | 4 | 1.27 / 2.69 | 1.27 / 2.09 | 1.00 / 1.96 | 1.00 / 2.20 | 0.94 / 1.73 | 0.96 / 2.05 |
| 4 | 0.5 | 4 | 1.26 / 2.31 | 1.28 / 2.08 | 1.20 / 2.06 | 1.02 / 1.78 | 1.18 / 2.16 | 0.94 / 1.53 |
| 4 | fit | 4 | 1.28 / 2.32 | 1.26 / 2.10 | 1.12 / 2.14 | 1.01 / 1.59 | 1.18 / 1.91 | 0.92 / 1.44 |
| 4 | zoom | 4 | 1.25 / 2.20 | 1.29 / 3.08 | 0.99 / 1.75 | 1.12 / 2.53 | 1.04 / 1.83 | 0.93 / 2.08 |
| 9 | 1 | 3 | 2.08 / 3.57 | 1.30 / 2.17 | 1.14 / 2.18 | 1.03 / 2.55 | 1.08 / 2.22 | 1.05 / 2.68 |
| 9 | 0.5 | 9 | 2.02 / 3.45 | 2.18 / 4.92 | 1.52 / 2.66 | 1.34 / 2.36 | 1.52 / 3.10 | 1.13 / 1.72 |
| 9 | fit | 9 | 2.07 / 3.37 | 2.10 / 3.38 | 1.59 / 2.87 | 1.55 / 2.91 | 1.75 / 3.12 | 1.33 / 3.52 |
| 9 | zoom | 3–9 | 2.05 / 3.10 | 2.04 / 3.35 | 1.44 / 2.57 | 1.30 / 2.37 | 1.35 / 3.28 | 1.04 / 1.64 |
| 16 | 1 | 4 | 3.25 / 5.11 | 1.62 / 2.85 | 1.41 / 2.73 | 1.27 / 2.15 | 1.24 / 2.02 | 1.14 / 2.09 |
| 16 | 0.5 | 8 | 3.32 / 5.85 | 2.22 / 3.40 | 1.55 / 2.82 | 1.47 / 2.47 | 1.45 / 3.33 | 1.28 / 2.20 |
| 16 | fit | 16 | 3.15 / 5.96 | 3.24 / 5.38 | 2.31 / 3.90 | 2.17 / 3.48 | 2.05 / 3.08 | 2.51 / 5.52 |
| 16 | zoom | 4–16 | 3.28 / 5.99 | 1.86 / 4.91 | 1.52 / 2.94 | 1.47 / 2.69 | 1.54 / 3.41 | 1.71 / 3.66 |

**vsync off: worst frame (ms)**

| Rooms | Scale | In view | A-always | A-visible | B-mips | B-linear | B-nearest | B-allmips |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 4.6 | 2.7 | 10.2 | 3.5 | 2.6 | 2.7 |
| 1 | 0.5 | 1 | 2.5 | 3.4 | 4.1 | 3.4 | 3.5 | 2.7 |
| 1 | zoom | 1 | 2.7 | 2.6 | 20.0 | 2.8 | 3.0 | 2.6 |
| 4 | 1 | 4 | 3.5 | 4.2 | 8.4 | 4.3 | 8.6 | 3.5 |
| 4 | 0.5 | 4 | 3.2 | 3.9 | 6.5 | 2.7 | 3.5 | 3.6 |
| 4 | fit | 4 | 4.4 | 4.4 | 16.7 | 3.3 | 3.7 | 2.9 |
| 4 | zoom | 4 | 7.2 | 5.4 | 3.1 | 5.1 | 21.6 | 3.6 |
| 9 | 1 | 3 | 5.1 | 3.2 | 8.2 | 6.4 | 20.5 | 3.9 |
| 9 | 0.5 | 9 | 4.9 | 6.8 | 4.4 | 3.6 | 4.5 | 3.1 |
| 9 | fit | 9 | 4.8 | 5.5 | 17.2 | 4.6 | 4.2 | 5.6 |
| 9 | zoom | 3–9 | 4.4 | 4.6 | 6.4 | 3.5 | 21.0 | 2.8 |
| 16 | 1 | 4 | 7.3 | 4.2 | 17.2 | 3.8 | 3.5 | 3.6 |
| 16 | 0.5 | 8 | 13.0 | 4.2 | 3.9 | 3.7 | 5.1 | 3.4 |
| 16 | fit | 16 | 7.9 | 7.5 | 5.5 | 4.9 | 4.3 | 10.5 |
| 16 | zoom | 4–16 | 18.9 | 6.7 | 4.3 | 4.9 | 5.3 | 5.4 |

**vsync on (360 Hz screen): median / 99th percentile (ms)**

| Rooms | Scale | In view | A-always | A-visible | B-mips | B-linear | B-nearest | B-allmips |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 2.78 / 3.08 | 2.78 / 3.08 | 2.78 / 3.01 | 2.77 / 3.08 | 2.78 / 3.02 | 2.78 / 3.08 |
| 1 | 0.5 | 1 | 2.77 / 3.05 | 2.78 / 3.03 | 2.77 / 3.40 | 2.77 / 3.08 | 2.77 / 3.05 | 2.77 / 3.08 |
| 1 | zoom | 1 | 2.78 / 3.10 | 2.78 / 2.99 | 2.77 / 3.00 | 2.77 / 3.07 | 2.77 / 3.02 | 2.78 / 3.05 |
| 4 | 1 | 4 | 2.78 / 3.10 | 2.78 / 3.02 | 2.78 / 2.98 | 2.78 / 3.33 | 2.78 / 3.05 | 2.78 / 3.19 |
| 4 | 0.5 | 4 | 2.78 / 3.10 | 2.78 / 3.00 | 2.78 / 2.96 | 2.77 / 3.05 | 2.77 / 3.07 | 2.77 / 3.06 |
| 4 | fit | 4 | 2.77 / 3.14 | 2.78 / 3.03 | 2.78 / 3.09 | 2.78 / 3.04 | 2.77 / 3.05 | 2.77 / 3.06 |
| 4 | zoom | 4 | 2.78 / 3.05 | 2.78 / 3.15 | 2.77 / 3.08 | 2.78 / 3.06 | 2.77 / 3.05 | 2.77 / 3.13 |
| 9 | 1 | 3 | 2.78 / 3.27 | 2.78 / 2.99 | 2.78 / 3.03 | 2.77 / 3.03 | 2.78 / 3.09 | 2.77 / 3.96 |
| 9 | 0.5 | 9 | 2.77 / 3.22 | 2.77 / 3.20 | 2.77 / 3.03 | 2.78 / 3.07 | 2.78 / 3.05 | 2.78 / 3.50 |
| 9 | fit | 9 | 2.77 / 3.59 | 2.78 / 3.02 | 2.77 / 3.09 | 2.78 / 3.02 | 2.78 / 3.04 | 2.78 / 3.27 |
| 9 | zoom | 3–9 | 2.77 / 3.90 | 2.77 / 3.04 | 2.77 / 4.11 | 2.77 / 3.03 | 2.78 / 3.05 | 2.77 / 3.07 |
| 16 | 1 | 4 | 2.81 / 5.15 | 2.77 / 3.02 | 2.77 / 3.88 | 2.78 / 3.06 | 2.78 / 3.05 | 2.78 / 3.16 |
| 16 | 0.5 | 8 | 2.90 / 4.55 | 2.78 / 3.07 | 2.77 / 3.22 | 2.77 / 3.04 | 2.77 / 3.10 | 2.78 / 3.07 |
| 16 | fit | 16 | 3.10 / 6.07 | 2.78 / 3.91 | 2.78 / 4.20 | 2.77 / 3.16 | 2.77 / 3.10 | 2.78 / 3.86 |
| 16 | zoom | 4–16 | 3.10 / 5.29 | 2.78 / 3.27 | 2.78 / 3.12 | 2.78 / 3.05 | 2.78 / 3.16 | 2.78 / 3.27 |

**vsync on: worst frame (ms)**

| Rooms | Scale | In view | A-always | A-visible | B-mips | B-linear | B-nearest | B-allmips |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 3.8 | 4.4 | 226.3 | 3.9 | 3.7 | 3.7 |
| 1 | 0.5 | 1 | 4.0 | 3.4 | 4.3 | 3.9 | 3.9 | 3.5 |
| 1 | zoom | 1 | 4.1 | 3.5 | 3.6 | 3.7 | 3.7 | 4.0 |
| 4 | 1 | 4 | 3.8 | 3.7 | 4.1 | 4.0 | 4.1 | 8.3 |
| 4 | 0.5 | 4 | 3.9 | 3.4 | 3.6 | 4.3 | 3.7 | 3.9 |
| 4 | fit | 4 | 4.6 | 3.6 | 10.0 | 3.8 | 3.9 | 4.0 |
| 4 | zoom | 4 | 4.1 | 3.7 | 5.5 | 4.1 | 3.4 | 14.2 |
| 9 | 1 | 3 | 4.6 | 3.4 | 3.5 | 3.8 | 4.4 | 6.7 |
| 9 | 0.5 | 9 | 4.3 | 4.5 | 4.0 | 3.7 | 5.8 | 16.2 |
| 9 | fit | 9 | 4.2 | 4.0 | 4.8 | 3.2 | 3.8 | 5.9 |
| 9 | zoom | 3–9 | 5.8 | 3.5 | 10.4 | 3.7 | 3.3 | 3.5 |
| 16 | 1 | 4 | 7.2 | 3.5 | 10.9 | 3.6 | 3.7 | 16.2 |
| 16 | 0.5 | 8 | 5.6 | 3.9 | 15.4 | 3.4 | 3.9 | 3.5 |
| 16 | fit | 16 | 9.8 | 5.3 | 7.3 | 4.2 | 3.6 | 5.3 |
| 16 | zoom | 4–16 | 146.2 | 5.0 | 4.2 | 3.8 | 3.8 | 5.7 |


**How to read the tables.**

* With **vsync on** this screen runs at 360 Hz, so every case is locked at 2.78 ms and the median says nothing. A frame that is slower than 2.78 ms is a missed refresh. The vsync-on tables only show that no case misses by much. A test at 60 Hz was **not** made on this machine.
* **Worst frames.** A few runs have one frame of 10 to 226 ms (for example `B-mips`, 1 room, scale 1, vsync on: 226 ms). They are not tied to a way. A rerun of the two worst cases, three times each, gave a worst frame of 3.8 to 8.0 ms. So these are one-off stalls (the operating system, or the first use of a resource). Do not read them as the cost of a way.
* The rows that matter for the overview and for flies are "fit" and "zoom" with 9 and 16 rooms.

**What the numbers say (vsync off, 16 rooms).**

| Case | A-always | A-visible | B-mips | B-linear | B-nearest | B-allmips |
|---|---|---|---|---|---|---|
| scale 1, 4 rooms in view: median / p99 | 3.25 / 5.11 | 1.62 / 2.85 | 1.41 / 2.73 | 1.27 / 2.15 | 1.24 / 2.02 | 1.14 / 2.09 |
| fit (all 16 in view): median / p99 | 3.15 / 5.96 | 3.24 / 5.38 | 2.31 / 3.90 | 2.17 / 3.48 | 2.05 / 3.08 | 2.51 / 5.52 |
| zoom: median / p99 | 3.28 / 5.99 | 1.86 / 4.91 | 1.52 / 2.94 | 1.47 / 2.69 | 1.54 / 3.41 | 1.71 / 3.66 |

* **A-always** pays for every room all the time: 16 rooms cost about 3.2 ms, whether one room or all are in view (1 room: 0.66 ms).
* **A-visible** removes that cost for rooms out of view (1.62 ms at scale 1). With all 16 in view it costs the same as A-always (3.24 ms).
* **B** costs about 2.1 to 2.5 ms with all 16 rooms in view, and about 1.3 to 1.6 ms when only some are in view. The mipmaps cost little: `B-mips` against `B-linear` is +0.1 to +0.2 ms at "fit".
* The gap between the ways is 1 to 2 ms at 16 rooms. The 99th percentile of the worst way (A-always, 5.99 ms) is still 2.8 times below 16.7 ms on this machine. A machine that is 3 times slower would put A-always near the limit and B-mips well under it. **This was not measured.**
* Draw calls: about 300 for 16 rooms in view, in both ways (about 19 for each room). Sprites of different sheets interleave in the depth sort, so they do not batch. In a zoom with 4 rooms in view, B uses about 80 calls.
* **Memory.** The working set of the process (read with `tasklist` at the end of each run) was 212 to 240 MB in every case, and it does not tell the ways apart: the engine and the driver are most of it. It also grew over the session (the first runs are the lowest). The video memory monitor of Godot with 16 rooms shows 42.5 MB for A and 31.7 MB for B (36.2 MB for `B-allmips`, which has copies of the sheets with mipmaps). The memory that Godot counts for scripts is 34.6 MB in all ways.
* **GPU time.** The column `gpu_ms_median` of the CSV comes from `viewport_get_measured_render_time_gpu` of the main viewport (0.07 to 0.23 ms). I do not trust it: it may not include the `SubViewport` passes, and the Compatibility renderer may not time the GPU well. Use the frame time.

### The picture

A screenshot of each way was taken at scale 0.5 (one room, at a whole-pixel position), at 0.25, at 0.37 (9 rooms), at the fit scale (16 rooms) and at scale 1. I looked at the pictures at 4 times their size. Each way draws the same moves. The check by number: the picture at scale 0.5 or 0.25 is compared with the picture at scale 1 that is shrunk by averaging 2x2 or 4x4 blocks (what a perfect shrink gives). The number is the mean absolute difference of the colour channels, from 0 to 255. Smaller is better. The pictures are not in the repository (image files are only allowed in `art/`).

| Way | Scale 0.5 (project snapping on) | Scale 0.25 (snapping on) | Scale 0.5 (snapping off) | Scale 0.25 (snapping off) |
|---|---|---|---|---|
| A-always, A-visible | 0.13 | 8.56 | 0.10 | 8.53 |
| B-mips | 2.53 | 4.79 | 0.30 | 3.50 |
| B-linear | 2.54 | 9.95 | 0.31 | 8.65 |
| B-nearest | 10.23 | 17.00 | 10.14 | 16.09 |
| B-allmips | 3.27 | 3.46 | 1.81 | 2.44 |

What I saw:

* **B-nearest looks wrong.** At 0.5, rows and columns are dropped: the clock is gone, the sign is a pile of dots, the bookshelf and the bench lose their lines. This is the problem that the mockup solves with smoothing. Do not use it.
* **A (a `SubViewport` with linear filtering) is exact at 0.5.** Bilinear sampling at exactly half size is the mean of 2x2 pixels. It looks right. **Below 0.5 it is wrong.** At 0.25 and at 0.37 the picture is crisp but not true: the sign text breaks up, the clock vanishes, and the blue band at the top has uneven dots. A bilinear lookup at 0.25 reads only 4 of the 16 source pixels. A `SubViewport` texture has no mipmaps, so it cannot do better. The overview of 16 rooms is at scale 0.24, so the overview is in the range where A is wrong.
* **B-mips looks right** at 0.5, 0.37 and 0.25. The room is the mean of its pixels at every scale. The clock and the plaster pattern stay. The props and penguins use linear filtering with no mipmaps, so at 0.25 they alias a little (the number 4.79). They are small, and I did not find it disturbing at 4 times enlargement.
* **B-linear** is as good as B-mips at 0.5 and as bad as A at 0.25 (it is the same lookup).
* **B-allmips** is the closest to a perfect shrink at 0.25, but the penguins and props get soft. I saw no colour fringes from the neighbours in the atlas. But mipmaps at the lower levels do read across the borders of atlas cells: this is a risk. It also had the highest p95 at "fit" with 16 rooms (4.8 ms against 3.2 ms for B-mips) in one run. I did not repeat it.
* I looked at still pictures only. Shimmer during a fly is **not judged**.

### Traps found

1. **A `SubViewport` has no mipmaps.** A scaled-down room is a bilinear lookup, which is right only at exactly 0.5 (and 1). Below that, it drops pixels. A possible fix that I did **not** try: a second, smaller `SubViewport` for each room at half size, and again at a quarter. It costs more passes.
2. **Update mode.** `UPDATE_ALWAYS` draws every room every frame, in view or not. `UPDATE_WHEN_VISIBLE` removes the cost of rooms out of view (3.25 ms to 1.62 ms for 16 rooms at scale 1). With all rooms in view the two modes are the same. I did not test what the first frame looks like when a room comes into view after a time out of view.
3. **Pixel snapping.** The project turns on `2d/snap/snap_2d_transforms_to_pixel` and `snap_2d_vertices_to_pixel`. With a scaled world they move every sprite to a whole screen pixel, so a sprite at a half-pixel position jumps and changes shape. The error at 0.5 of B-mips is 2.53 with snapping and 0.30 without (`--s6-snap=off`). A is not affected (the picture is one quad). **I did not test snapping off at scale 1.** Positions are whole numbers there, so it should not matter.
4. **Filter flags.** In way B the room node and the sprite node have their own `texture_filter`. The flag `LINEAR_WITH_MIPMAPS` does nothing for a texture with no mipmaps. The imported room PNGs have **no mipmaps** (`mipmaps/generate=false`, and `test_atlas.gd` checks this). The spike makes a copy with mipmaps at run time (`art/s6_support.gd`). The other way is to set `mipmaps/generate=true` in the `.import` files of the five room PNGs, and to change the test. **This needs a decision.** In way A the `SubViewport` has its own `canvas_item_default_texture_filter`: the spike sets it to nearest. The default value was not checked.
5. **The sign.** `RoomArt` draws the sign with the glyph sheet. The glyph sheet has no mipmaps, so at 0.25 the sign is a bilinear lookup and is not readable. This holds for all ways. A readable sign in the overview needs another solution (for example, no sign text below a scale, or a letter on the tab).
6. **Sprites do not batch** in a room with the depth sort (see draw calls above). About 300 calls for 16 rooms is no problem here. The count will grow with the effects and the interface of the real client.
7. **Culling.** Sprites out of the view are culled by the renderer (way B). The simulation (`tick`) still runs for every room in both ways.
8. **`get_viewport().get_texture()` of the root viewport is 480x270** (the stretch mode `viewport`). The pictures have that size.

### Rules that got in the way

* **The license check forbids `ImageTexture`, `_draw`, `draw_*` and `set_pixel` outside `art/`.** It scans `test/` and `spikes/` too. The room needs a node that calls `RoomArt.draw_sign` (it draws on a `CanvasItem`), and way B needs a texture with mipmaps. Both are art code, so they are in `art/s6_support.gd` with the copyright header. The rest is only sprites and `SubViewport`. The rule was not weakened. **Decision for the owner:** delete `art/s6_support.gd` with the spike, or keep the part that G-5 uses. (Phase G-5 does not use it: the mipmaps come from the import setting of the room PNGs. See "Open questions (phase G-5)".)
* `test/test_s6_stats.gd` builds its images with `Image.new()` and `set_data()`, because `Image.create` and `set_pixel` are on the list.
* `tools/check_scripts.gd` now also loads the scripts in `spikes/` (it had only `src`, `art`, `test` and `tools`). This makes the check stricter, not weaker.

### Recommendation for G-5

**Use one shared world (way B). Draw the room from a texture with mipmaps and trilinear filtering (`B-mips`). Use linear filtering for the sprites. Do not use a `SubViewport` for each room.**

Reasons:

1. **The picture.** It is the only way that is right at every scale. The overview of 16 rooms is at scale 0.24, where a `SubViewport` is wrong (the number 8.6 against 3.5 to 4.8) and the sign and the fine patterns break up.
2. **The cost.** With all 16 rooms in view: 2.31 ms median and 3.90 ms p99, against 3.15 and 5.96 for `A-always`. With part of the grid in view (most of a fly): 1.4 to 1.6 ms, against 3.3. `A-always` pays 3.2 ms for 16 rooms even when one room is in view.
3. **Memory.** 31.7 MB of video memory against 42.5 MB for 16 rooms, and no render target for each room.
4. **It is the design of the plan** ("Arenas in one world"). The room texture and the sprites are what G-3 already builds.

What to do in G-5:

* Give the room textures mipmaps (an import setting or a copy). Set the room node to `LINEAR_WITH_MIPMAPS` and the sprite node to `LINEAR`. Use `NEAREST` for scale 1. Keep the filter in one place, so that it can change with the scale.
* Turn off `snap_2d_vertices_to_pixel` for the scaled world (check `snap_2d_transforms_to_pixel` too). Round the positions of the sprites in the room yourself (`floor(x + 0.5)`, as `Atlas.draw` does).
* Hide the rooms that are out of view, if the culling of the engine is not enough once the interface is drawn.
* For soft penguins at 0.25 (`B-allmips`): pad the atlas cells with a few empty pixels first.

If the owner wants way A for another reason (for example an effect over the whole room), use `A-visible`, accept the aliasing below 0.5, and draw the overview rooms from a mipmapped copy of the picture instead.

### What was checked, and what was not

* Checked: 180 runs on one machine (all cases, vsync off and on); the pictures of all six ways; `node tools/check.mjs` (36 scripts, no warnings); `node tools/run-gut.mjs` (131 tests pass); `node --test` (57 pass, 1 skipped by an existing test; none of the new files skip).
* **Not checked:** a low-end laptop or any integrated GPU; a 60 Hz screen (vsync on ran at 360 Hz); another OS or another driver; a run with the real G-4 and G-6 content (effects, text, the interface) on top of the rooms; moving pictures (only still pictures were judged); `UPDATE_WHEN_VISIBLE` after a room comes back into view; snapping off at scale 1; the GPU time (the monitor is not trusted).
* The laptop had other programs open during the runs. The one-off stalls probably come from that.

## Phase G-4: behaviour and scenes

The room is alive. The director reads events and gives each agent a penguin. The actor walks the penguin through the stations.
The effects are drawn from the clock and from seeded random numbers. The events come from the bridge or from a timeline file.

```bash
"$GODOT" --path .                          # in godot/. The bridge, one room (start a bridge and a replay first)
"$GODOT" --path . -- --demo=session        # a scene of demo/, no bridge
"$GODOT" --path . -- --demo=multi --speed=2
```

### What was added

| File | Content |
|---|---|
| `src/core/clock.gd` | The simulation clock. A step is 1/60 s. `advance(frame_time)` says how many steps to run. A frame counts at most 0.1 s. Speed and pause live here. |
| `src/core/world.gd` | What the actors share in one room: the time, the spots, the effect cues, the actors. An actor does not keep a reference to it (no reference cycle). |
| `src/core/director.gd` | One penguin for each framework + session + agent, helpers, the limit, the cord colours, the backlog rule, the focus. |
| `src/core/penguin_actor.gd` | The state machine of one penguin or helper: an event queue and a list of motion segments. It exposes position, facing and pose. |
| `src/core/effects.gd` | The effect cues (dust, puff, spark, smoke, tink, bell, confetti, sparkle) and the shake of the room. No drawing. |
| `src/core/focus.gd` | The focus: AUTO and MANUAL, the hold. |
| `src/core/backlog.gd` | The backlog rule. |
| `src/core/frame_policy.gd` | The frame cap without focus and the stop when minimized, as pure functions. |
| `src/net/timeline_player.gd` | Demo mode: hands on the events and the inputs of a timeline file. Lists the scenes of `demo/`. |
| `src/view/live_view.gd`, `src/live.tscn` | The live room: the frame loop, the source, the keys, the window policy. It is the main scene now. |
| `src/view/penguin_view.gd` | Turns an actor into the dictionary that the art node draws. |
| `art/effects_art.gd` | Dust, puffs, sparks, the fire of the forge, smoke, stars, confetti, the thought cloud with its candle, the stars around a flop. Art: it has the header. |
| `art/status_art.gd` | A plain status bar and the list of scenes. It stands in for the bar of phase G-6. Art. |
| `art/room_stage_art.gd` | Changed: small penguins (the helper), the flop with its cap, and the hooks for the effects. |
| `tools/export-scenes.mjs` | Makes `demo/session.json` and `demo/multi.json`. |
| `tools/run-gut.mjs` | Changed: it fails when GUT ignores a script or runs too few scripts. |
| `art/images/props.png` and the baker | Two new pictures: `prop/cloud-mini` and `prop/candle/2` (see decision 17). |

### What a penguin does

| Event | The penguin |
|---|---|
| `session_start` | pops in near the rug with a puff. It does nothing else. |
| `tool_start` | walks to the station of its `category` and takes the pose of the spot, until the `tool_end`. A full station gives a line. |
| `tool_end` | stops. With `ok: false` the penguin flops for 1.8 s, the room shakes, and a failed run at the forge makes smoke. |
| `waiting_permission` | goes to the sign post at once (it cuts a walk) and waves until the next event. Then it makes a small cheer (0.45 s). |
| `thinking`, or a tool of category `think` | goes to the armchair when it is free. Otherwise it thinks where it stands. A cloud with a candle shows. |
| `done` | walks to the stage and celebrates for 4 s, with confetti. |
| `subagent_start` | makes a small helper. It pops in at the helper desk, waves, and walks to the telescope. |
| `subagent_end` | the helper vanishes with a puff. |
| `error` | flops where it stands. |
| any other type | generic work at the odd-jobs station for 1.2 s. |

### Decisions of phase G-4

The owner was asleep. These are my choices. Each one can change.

1. **Segments and local time.** The actor has a list of segments (pop, idle, walk, hop, work, queue, think, sit, approve, flop, cheer, wave,
   vanish). Each segment has an age. `hurry()` is 1.0 with at most one event waiting. Each further event adds 0.5, up to 4.0. The actor's
   age grows by `dt * hurry`. So a queue speeds up walking, working and the animation together.
2. **When the next event starts.** A script ends before the next event starts. A segment that waits for an event stays at least a
   minimum time: 0.9 s for work, 1.0 s for a wait, 1.2 s for thinking, 0.3 s for a line. A call whose end is already in the queue still
   walks to its station and works 0.9 s. So every station shows (the trace test needs this). A long burst gets the hurry.
3. **Speeds and times** come from the mockup: walking 150 px/s (helper 120), pop 0.35 s, flop 1.8 s, hops 0.25 s and 0.22 s, the walk
   frame 0.13 s. The walk is a straight line, as in the mockup. The first version has no path around props.
4. **Thinking.** The armchair when it is free, and otherwise in place (decided in the 2D view plan). The spots `spotA` and `spotB` stay
   in `stations.gd`, but the actor does not use them. This answers question 3 of phase G-3. A sitting penguin hops down before it goes on.
5. **A prompt for a permission.** `waiting_permission` cuts a walk. The tool call that was open becomes "suspended". The next event
   ends the wait: the penguin makes the small cheer, and the event is then handled. A `tool_end` of the suspended call closes it, and
   `ok: false` flops at the sign post. There is no walk back to the station: no adapter says that the approval came, only the next event does.
   A second prompt while the penguin waits changes nothing. This also fits a `tool_start` that comes just before its prompt (Claude Code):
   the penguin never walks to the forge.
6. **A `tool_end` of a call that the penguin left** is ignored, unless it failed: then the penguin flops.
7. **Delegation.** The bell rings for 1.0 s at the desk, and then the penguin stands there until the `tool_end`. The mockup leaves the
   desk after the bell. The call is open in live data, so staying is the honest picture.
8. **A finished turn.** The stage point of the mockup (344, 168). A second and a third penguin get other places beside it
   (`STAGE_OFFSETS`), so that two penguins do not stand on one point. The confetti lasts 4 s, as in the mockup.
9. **Rest.** A penguin that has had nothing to do for 2 s walks to its rest point. It is the point where it popped in near the rug
   (the helper: the telescope). A new event cuts this walk. This is mine. The mockup keeps no penguin idle. Without it, a penguin would
   stand on a spot of a station for the whole time that its agent is quiet.
10. **Spawn.** Six points near the rug (the start points of the scene `multi`), used in turn.
11. **Helpers.** The key of a helper is framework, session and the `id` of the subagent event. Events whose `agent` is this id go to the
    helper. A helper with its own events works at stations like a penguin. It has only a few small pictures (the poses wave, walk, idle, peer),
    so a helper shows the small standing picture for other poses. A helper does not count for the limit. It wears its parent's number
    and cord. Add small pictures to `variants.js` if the helper should show its tools.
12. **The limit on penguins** is a setting (`Director.limit`, `--limit=`), 12 by default. An agent over the limit gets no penguin, and
    its events are dropped and counted (`dropped_agents`). A penguin never leaves in phase G-4, so a slot is not free again. Phase G-5
    adds `leaveAfter`.
13. **The backlog rule.** When a queue is longer than 20 events, it drops the oldest events that no longer matter, and stops at 20. It
    keeps the last 6 events, every `done`, an open prompt, and a call that is still open. It drops finished calls (start and end together),
    `thinking`, `error`, answered prompts, and unknown types. A queue can stay longer than 20 when all that is left must stay.
14. **The cord.** A framework with a cord in the atlas gives its own cord. Any other framework gives `default` (grey, as in G-2).
    A test compares the list of frameworks with `CORDS`.
15. **The focus.** AUTO follows the newest event, held 1.5 s. A failure, a prompt, an error and a finished turn take it at once, and
    the priority is used up (it does not pin the focus). It is the rule of `simulateCamera`. Two details are mine: a click sets the focus
    in both modes and holds it 1.5 s in AUTO. And MANUAL drops the priority events that come while it is on, so that going back to
    AUTO does not jump to an old event. The ring and the label are G-6. The focus shows in the status bar.
16. **Effects.** The actors only say what happened (cues). The art draws a cue from its age. Sparks come only at the first forge spot (the
    shovel). The mockup has none at the hammer there. Stars come from the hammer and the bell. The forge fire is drawn again each 0.1 s from
    `mulberry32`. The shake follows `shakeAt`: 0.4 s, at most once a second. Not drawn yet (they are in the mockup, and phase G-6 or later
    may add them): the "..." bubble of a penguin in a line, the ribbons, the notice at the sign post, the chips, the tags, the focus ring.
17. **Two new pictures.** The small cloud of a penguin that thinks in place (`prop/cloud-mini`, from `crowd-art.js`) and the candle with 2
    steps of wax (`prop/candle/2`). I rendered `props.png` again with `render-art.mjs`. Only that sheet and the lists changed. A test
    in `art-render.test.mjs` still finds the cloud and candle blocks in the mockup. The mini cloud has its own marked section in `effects_src.js`.
18. **A pose with no blink picture** shows with open eyes. Before, a penguin was not drawn for 0.12 s when it blinked in a pose that has
    no blink picture (a cheer). A test finds this.
19. **Demo mode.** A timeline holds `{t, event}` and the inputs of a person (`{t, key: "F"}` or `{t, click: {number}}`). The player hands
    on what is due. Pause and speed belong to the clock, so the whole room, not only the events, goes faster. When a scene ends, the
    room waits 2.5 s and starts again with no penguins. The scene list is the files of `res://demo/`. The menu is a plain list in the
    status bar. Its keys are mine (D, Up, Down, Enter, Esc), because 1 to 4, S, E and M are for the sound.
20. **The window.** Focus: no cap. No focus: 30 frames a second (a setting). Minimized: no drawing, and 10 frames a second for the
    simulation. A window that starts in the background asks `has_focus()` at the start, because it never gets a focus signal.
    The simulation step stays 1/60 s in all cases.
21. **The main scene** is now `src/live.tscn`. The text view of phase G-0 is `src/main.tscn`.
22. **`tools/shot.gd`** can take several pictures (`--count`). `Options` accepts its arguments with no warning.

### The timelines (`tools/export-scenes.mjs`)

The mockup scripts the motion as segments with times. The client reacts to events. So the tool turns each scripted action into the events that
make the client do the same. It runs `crowd.js`, `multi-agent.js` and `session.js` in a Node `vm` with a few stubs (`window`, `matchMedia`,
`document.fonts`). **It needs no browser.** The mockup is not changed. The tool reads the times of the input of `multi` (the F key and the click)
from the source text, and fails when it does not find them.

| Scripted action | Events |
|---|---|
| a call at a station | `tool_start` at the start of the walk, `tool_end` at the end of the work (`ok: false` and an `error` for a failure) |
| thinking (armchair or in place) | `thinking` at the start |
| a call that needs approval | `tool_start` and `waiting_permission` at the same time, `tool_end` when the answer comes |
| work for a helper | `tool_start`, `subagent_start` when the helper appears, `tool_end` when the penguin leaves the desk, `subagent_end` |
| a finished turn | `done` at the start of the walk to the stage |
| a penguin that joins | `session_start` |

`session.json` has 22 events (28.5 s). `multi.json` has 57 events (30.5 s) from six agents of four frameworks, and two inputs. `ts` is a
fixed epoch time plus `t`. The targets are the made-up text of the mockup. `tools/export-scenes.test.mjs` checks each event against
`schema/event.schema.json` (a small checker for the keywords that it uses) and against `validateEvent` of the bridge. It also checks the order of
the times, the pairs of start and end, the fields, a few signs of a real path, the story, and that the files are what the mockup gives now.

What differs from the mockup: the client chooses the spots from the categories (the mockup scripts them), it walks straight (the session
mockup walks round a point to the workbench), a thinking spell ends with the next event, and a finished turn is celebrated at the stage
point (the session scene of the mockup celebrates on the rug).

### The behaviour trace

`test/fixtures/expected-trace.json` holds the visits of three runs, with no language in it. `test_behaviour_trace.gd` plays the events in
steps of 1/60 s and compares.

| Run | Visits of `agent 1` |
|---|---|
| The real Claude Code example (`claude-code.events.jsonl`) | Thinking chair, Map table, Bookshelf, Workbench, Forge, flop, Helper desk, Telescope, celebration. The helper goes to the Telescope. |
| The made-up session (`demo/session.json`) | Map table, Bookshelf, Thinking chair, Workbench, Helper desk, Forge, flop, Workbench, Forge, Sign post, celebration. The helper goes to the Telescope. |
| The scene `multi` | one list for each of six agents (see the file) |

**The plan's list is not the list of the real example.** The plan says: map table, bookshelf, workbench, forge, sign post, flop, helper desk and its
helper, telescope, workbench, forge, celebration. The real example has no prompt for a permission, and it runs each tool once. Its flop comes
at the forge. The made-up session has the prompt, the flop and the second visit to the workbench and the forge. Its story order is the story of the
mockup. All stations of the plan's list are in it. A test checks them as a set, and that the celebration is last.
The same test plays the session with a frame rate of 30 and one of 144, and the trace is the same.

### Screenshots I looked at

With `tools/shot.gd` on this Windows machine (Godot 4.7.2, OpenGL window, an NVIDIA laptop GPU):

* `--demo=session` at 2.5, 4, 6.5, 7.5, 10, 12.5, 14, 15.5, 17, 19, 24 and 27 s. Map table, bookshelf, the armchair with the cloud and the
  candle, the workbench with stars, the desk with the helper, the forge with sparks, the flop with the cap on the floor and the smoke,
  the sign post, and the celebration with confetti. The helper stands at the telescope until its end.
* `--demo=multi` at 3.5, 6.8, 9.5, 12.8, 17, 25 and 29.5 s. Six penguins, the thought clouds in place and at the armchair, a line at the sign post,
  the pinned focus (`focus: 4 pi`, MANUAL) after the scripted F key and click.
* A live session: a bridge on another port, and the four example sessions (Claude Code, OpenCode, Pi, Hermes) posted at the same time.
  The room shows four penguins and one helper, and the status bar says `4 agents, 1 helper`. Earlier, `npm run replay` of the Claude Code
  transcript showed one penguin that goes from the armchair on its way through the stations.
* I did **not** put them next to stills of the mockup, pixel by pixel. The effects follow the mockup's code, with its numbers. I compared
  them by eye with the two preview pictures of `docs/images/` (`arena-2d-preview.png`, `arena-2d-multi-agent.png`): the armchair with the
  big cloud and the candle, the small clouds of the penguins that think in place, the cap cords, and the confetti look the same. What the
  previews show and the client does not yet: the notice at the sign post, the number chips, the tags, the ribbon, the cards and the bar (phase G-6).
  The cap cord colours are small at this size: I saw the cord on the penguins of the four frameworks in the live session, but not at full size.

### The cost of the simulation

`test_simulation_cost.gd` steps 157 agents with a call each, 600 steps. On this machine one step takes about 1 ms (the plan's limit is 10 ms).
It is not the reference machine.

### The window policy, checked

I ran the live room in a window, minimized it with `DisplayServer.window_set_mode`, and looked at `Engine.max_fps` and the render loop. Focused:
no cap, 430 frames in 1.5 s. Minimized: `max_fps` 10, `render_loop_enabled` false, 21 frames in 2 s. After the restore: no cap, drawing on. **Not
checked:** a real loss of focus to another window (the unit tests call the handler), and macOS and Linux.

### What was checked, and what was not

* Checked: `node tools/run-gut.mjs` (29 scripts, 291 tests, all pass), `node --test` in `godot/` (83 tests, all pass), `node tools/check.mjs` (no warnings),
  `npm test` of the mockup (38 pass), `npm test` of the bridge (45 pass), and the screenshots above. `run-gut.mjs` fails on a script with a parse error (tried with a
  broken test file).
* Not checked: the speed of the frame on the reference machine, a run on macOS or Linux, the sound (phase G-7), a real focus change, the
  cord colours of OpenCode, Pi and Hermes at full size, and the look of the status bar (it is a stand-in).
* An export has to include `demo/*.json` (phase G-9). The scene menu lists the files of `res://demo/`.

### Open questions (phase G-4)

1. **Penguins over the limit** are dropped, and a slot is never free again before G-5. Should the oldest quiet penguin leave instead?
2. **Rest walk.** A quiet penguin walks to the rug after 2 s. Is it wanted, or should it stay where it is, as in the mockup?
3. **The delegating penguin** stands at the desk until the call ends. Should it leave, as in the mockup?
4. **Tool poses for helpers.** A helper with its own events shows a small standing picture. Do you want small pictures of every pose?
5. **Minimum work time.** A call works at least 0.9 s. A very fast session therefore runs behind the agent and hurries. Do you want a shorter minimum?
6. **Shipped scenes.** `demo/*.json` is in the app folder. Question 12 of the plan (ship the timelines) stays open.
7. **Thinking in place** uses the rule of the 2D view plan. The two extra spots of the table (`spotA`, `spotB`) now have no user. Remove them from
   `stations.gd` or keep them?
8. **The approval has no end event.** The wait ends with the next event. A real adapter that reports the answer would make the picture exact.

## Phase G-5: arenas and camera

The arena model runs on live events, the camera is incremental, and the view draws what the camera sees. The scenes `arenas`, `many`, `follow` and `ten` play from timelines.

```bash
"$GODOT" --path . -- --demo=arenas                  # in godot/. Also: many, follow, ten
"$GODOT" --path . -- --demo=ten --speed=2 --arena-size=4 --leave-after=600
"$GODOT" --path . -- --benchmark=ten --benchmark-out=run.csv --vsync=off     # needs a window; see "The first performance run"
node tools/benchmark-report.mjs run.csv
```

Keys of the camera: `F` (AUTO or MANUAL), `Tab` (the overview, on and off), `Esc` (leave the overview), `Left` and `Right` (the previous or next arena, or a page in the overview), `N` (the arena that needs you). A click on a room in the overview zooms into it. The bar with the tabs and the page boxes is phase G-6, so a click on a tab or a page box has no place yet: the camera has the methods (`click_tab`, `click_page`), and a timeline can use them.

### What was added

| File | Content |
|---|---|
| `src/core/camera.gd` | The incremental camera. It takes events while they happen, runs the rules every 1/30 s, and gives the pose at any time. |
| `src/core/director.gd` (changed) | One world for each arena, the arena model, `leave_after`, the first penguin of a new arena, the feed of the camera. |
| `src/core/penguin_actor.gd` (changed) | The segment kinds `hidden` and `gone`, `leave()`, the fields `arena` and `leaving`, a `delay` for `start()`. |
| `src/core/clock.gd`, `src/net/timeline_player.gd` (changed) | A scene may start before time 0 (`Clock.reset(start)`, `start_time()`). A timeline may have `options`. |
| `src/core/options.gd` (changed) | `--arena-size`, `--leave-after`, `--follow=manual`, `--benchmark`, `--benchmark-out`, `--vsync`. |
| `src/view/arena_view.gd` | The camera view: the world node, the room nodes, the filter, which rooms are in view, the free places, the page numbers. |
| `src/view/live_view.gd` (changed) | Director, camera and view together. The keys. The benchmark mode. |
| `src/core/bench_log.gd` | The text of the benchmark log. |
| `art/ribbon_art.gd`, `art/world_art.gd` | The ribbon of a new arena. The free places, the page numbers and a panel over the rows below the room. Art. |
| `art/room_stage_art.gd`, `art/effects_art.gd`, `art/status_art.gd` (changed) | The ribbon, the `far` switch, a public `sparkle`, the line of the view in the status bar. |
| `art/images/room_*.png.import` (changed) | `mipmaps/generate=true` for the five rooms. |
| `tools/export-scenes.mjs` (changed), `demo/{arenas,many,follow,ten}.json`, `test/fixtures/scene-reference.json` | The four scenes, and what the mockup decided for them. |
| `tools/benchmark-report.mjs` | Reads the CSV and the camera moves of a benchmark run and prints the windows of long moves. |

### The incremental camera

`Camera` gives the same results as `ArenaRules.simulate_camera`, but it does not read the future. The batch port knows when an approval ends (`until`). The incremental camera marks an approval as open until `answer()` says that it ended. The batch port stays as the oracle. It was not changed.

```gdscript
const Camera := preload("res://src/core/camera.gd")
var camera := Camera.new({ "reduced_motion": false })
camera.arena_opened("A", 0.0)                      # the first arena is where the camera starts
camera.feed("approval", "B", 5, now)               # returns the id of the pull: camera.answer(id, later)
camera.feed_focus("B", 5, now, true)
camera.press("Tab", now)                           # the person's inputs are queued with a time
camera.advance(now)                                # runs the steps of 1/30 s up to now
var pose := camera.pose_at_time(now)               # smooth between the steps
```

* **Decisions of the camera are every 1/30 s, and the pose is a function of the time** (choice 4 of the plan). `pose_at_time(t)` is `pose_at(move, t, width)`.
* **The feed.** `feed(kind, arena, n, t)` takes the kinds of `simulate_camera`: `activity`, `fail`, `open`, `join`, `done`, `approval`. Every event is activity. The camera keeps only what the rules need: the newest activity of each arena, the pulls that are not over, and, for `N`, the failures and finished turns that no later event of the agent has replaced. So a long session does not grow without end. `log` and `moves` keep the last 10000 moves.
* **Events must not be dated in the future.** The batch camera reads an event of the future by its time and skips it. The incremental camera takes what it is given as having happened. The director and the tests feed an event at its time.
* **An answer.** `answer(id, t)` and `answer_agent(n, t)` end an approval at `t`. An approval that was never answered pulls for as long as it waits. The camera forgets an approval only when it ended.
* **The person's inputs** are `press(key)`, `click_tab`, `click_cell`, `click_page`, `toggle(kind)`, `manual_only()`, `set_pace(p)` and `input({...})`, which is the form of the batch spec. They are queued with a time, and the next step applies them, as the batch camera applies the inputs of its spec.
* **A click on a penguin** (`set_focus(arena, n, t)`) sets the focus in both modes and holds it for the focus hold in AUTO. The batch camera has no such input, so the golden data do not cover it. The scene `multi` has this click.
* **Signals** for the interface of phase G-6: `moved(entry)`, `mode_changed(mode)`, `ribbon_started(arena, at)`, `held_changed(held)`. Each move has an id. `moves` holds `{id, t, to, why, kind, apart, dur, peak, wide}`. `kind` is `slide`, `fly`, `zoom`, `scroll` or `cut`. `wide` is true when the view widens to 4 rooms across or more. `log` has only `{t, to, why}`, as the batch camera.
* **Reduced motion** is `set_reduced_motion(true)` (or the option). Every move is a cut of 0.15 s. The view fades out and in (see below).

The tests: `test_camera_parity.gd` runs every golden camera case (the 47 cases of `arena_rules.json` and the four scene files) through the incremental camera, with the events fed at their times and each approval answered when its `until` time has come. The log and every frame must agree with the JavaScript within 1e-9. It also compares the incremental camera with the batch port on a busy script of 120 events. The live-only cases are in the same file: an approval that opens and is answered later, one that is never answered, an answer before the camera may move, a pull for an arena that closes, the arena on screen that closes, events that arrive between two steps, the pace and the `held` signal, reduced motion, the signals, the marks of the long moves, the log limit, and the click on a penguin.

### The arena model in the director

The director places each new penguin with `ArenaRules.create_arenas`. The rules are in `docs/2d-arenas-plan.md`. The settings are off by default, so a director on its own behaves as before (one room, no leaving).

| Setting | Default of the director | Default of the view | Meaning |
|---|---|---|---|
| `arena_size` (`set_arena_size`) | 0 (one room for everyone) | 4 (`--arena-size`) | Agents in an arena. Helpers do not count. |
| `leave_after` | 0 (off) | 600 s (`--leave-after`) | An agent with no event for this long leaves, unless a call or an approval is open. |
| `limit` (the `maxPenguins` of the plan) | 12 | 200 (`--limit`) | The most penguins in all arenas. |
| `close_after` | 30 s | 30 s | An empty arena closes after this long. Never the last one. |
| `new_penguin_delay` | 0.6 s | 0.6 s | The first penguin of a new arena pops in this long after the arena opens. |

Decisions:

1. **One world for each arena.** `rooms` maps a letter to a `World` (spots and queues, effect cues, actors). Two penguins in different arenas can stand on the same spot. `director.world` is the world of arena A, so the code and the tests of phase G-4 still work with one room. `Spots` work for each arena because each world has its own.
2. **An agent never changes arena.** An actor has `arena`. A helper has the arena of its parent.
3. **A penguin that leaves** frees its place in the arena at once (the plan: "its place and number are freed" when it starts to walk out). It walks to the door and out of the room (`Stations.point("door")`, `"out"`), and the director removes it when it is gone. Its key is renamed, so a new event of the same agent makes a new penguin with a new number, as the plan says. Its helpers vanish. The check runs every 0.5 s.
4. **An empty arena closes** after `close_after`, and its room is removed. The lowest free letter is used again. The first penguin of a new arena waits 0.6 s as a `hidden` segment, with the puff at the end. This is only for arenas that open after time 0: a scene that starts with agents already there has no delay (the mockup's `t > 0`).
5. **The focus of an arena is the camera's.** With a camera, the director gives focus events to the camera and not to its own `Focus`. `Focus` stays for a director with no camera (the tests of phase G-4).
6. **What the director tells the camera.**

| Event of the agent | The camera gets |
|---|---|
| a new agent in a new arena (after time 0) | `open` (a pull, ticked by default) |
| a new agent in an arena with room (after time 0) | `join` (not ticked by default) |
| `waiting_permission` | `approval`, open until the next event of the agent |
| `tool_end` with `ok: false`, `error` | `fail` |
| `done` of a main agent | `done`. A helper's `done` is `activity`: a helper never pulls. |
| any other event, `session_start`, `subagent_start`, `subagent_end` | `activity` |

   The approval ends with the next event of the same agent (not a helper, not a second prompt). This is decision 5 of phase G-4: no adapter says when the answer came, so the next event does. `subagent_start` and `subagent_end` count as activity of the arena, because every event is activity. The mockup's camera does not count its helper work (see "The camera log against the mockup").
7. **Names after Z, the lowest free letter, going back to the old arena** are the rules of `create_arenas`. Nothing is changed there. `test_director_arenas.gd` tests the use: the size of an arena, helpers, no change of arena, the limit, the delay, leaving, calls and approvals that stop it, a returning agent, closing, never the last arena, the lowest free letter, names after Z, and what the camera is told.

### The camera view

`ArenaView` is one shared world (way B of spike S-6). Each arena is a room node (`RoomStageArt`) at its place on its page. The world node is moved and scaled by the camera pose: the scale is 1 divided by the rooms across (1 for one arena, 0.5 for a page, 0.125 for the widest fly). Rooms are 480x232, a page is 2x2 with a gutter of 0.1 of a room (48 px at scale 1).

* **Whole pixels at the scale of one arena.** At `s = 1` the world position is rounded, also during a slide, and the filter is nearest. The sprites are placed on whole room pixels by `Atlas.draw`, as before.
* **Smooth scaling elsewhere.** The five room PNGs have `mipmaps/generate=true`. The rooms use `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` when `s` is not 1. The sheets of sprites have no mipmaps, so the same flag gives them plain linear filtering: one node per room is enough (the spike used two). `test_atlas.gd` now says that only the rooms have mipmaps.
* **No vertex snapping.** `project.godot` has `snap_2d_transforms_to_pixel=false` and `snap_2d_vertices_to_pixel=false` (both: with the second one off, the first still moved the scaled rooms).
* **Rooms out of view are hidden** (`visible = false`). The view does not even give them their penguins: it gives data only to the rooms that touch the 480x232 view. The simulation of every arena goes on.
* **Far rooms are simple.** Below a scale of 0.4 (`FAR_FROM = 2.5` rooms across) a room has no glow, no effects and no shadows. They are too small to see, and the glow of the forge is five ellipses of one rectangle for each row. This is the decision that made the long moves fast: see "The first performance run".
* **The free places** of a page in view are dark cells (`#161c2e`, one pixel gap when the view is wider than 1.5 rooms), as in the mockup. The **page numbers** show below the pages when the view is wider than 3 rooms (fully from 4.5), and the page of the camera's target is gold.
* **The sign** says AGENT WORKSHOP for one arena and ARENA B and so on for several. The **ribbon** "ARENA B" on the wall (with six gold sparkles) shows for 2.6 s when the camera first shows a new arena (`camera.ribbon`).
* **Reduced motion** is a fade in place of the crossfade of the mockup: the view shows the old pose and fades out, then the new pose and fades in (0.15 s in all).
* **The rows below the room** (232 to 270) get a plain panel over the world, so a room scaled up in a slide does not show there. The status bar is a stand-in for the bar of phase G-6. It has the line of the view ("arena B, page 1 of 3").
* **The sign is not readable** at the scale of the overview. It is not fixed here (G-6 shows a letter on the tab).

### The scenes

`tools/export-scenes.mjs` now makes `demo/arenas.json` (95 events, 43 s), `many.json` (785 events, 53 s), `follow.json` (739 events, 50 s) and `ten.json` (4006 events, 54 s, 640 KB). It runs `arenas.js` with the scene's own scripts in a Node `vm`, with a stub in place of the drawing code. So it needs no browser, and the mockup is not changed. The events are made from the crowds that the mockup built, as for `multi`.

* **The mockup places the agents, the client does it again.** The tool writes only the events. What the mockup decided (the arena of each agent, when each arena opened and closed, and the camera log) is in `test/fixtures/scene-reference.json`, made by the same tool. `export-scenes.test.mjs` checks that the arena model gives the arena of the mockup for the order of the events. `test_scene_camera.gd` checks that the client does too.
* **The first event of a new arena** (`session_start`) has the time at which the arena opens. The mockup shows the penguin 0.6 s later. The director waits for the 0.6 s.
* **Scenes that start with agents there.** `many`, `follow` and `ten` start with 22, 30 and 150 agents. Their `session_start` has a time of -3, and the clock starts at the first event. The view runs this before the first frame (`_run_preroll`). Events with equal times go in the order of the agent numbers, which is the order in which the mockup's model placed them.
* **Options of a file.** `"options": {"arena_size": 4}` for the arena scenes, with `follow` for the scene `follow` (it starts with every kind ticked). `session.json` and `multi.json` now have `"options": {"arena_size": 0}`: one room, as the mockup. `--arena-size=` wins over the file.
* **Inputs** are the mockup's (`{t, key}`, `{t, click: "tab"|"cell", arena}`, `{t, click: "page", page}`, `{t, toggle}`, `{t, manual}`, `{t, pace}`). The camera gets them as they are.
* The scene menu lists the files of `demo/`, so the four scenes are in it.

### The camera log against the mockup

`test_scene_camera.gd` plays each scene through the real `LiveView` and compares its camera log with the mockup's. The rule of the plan: the same moves, in the same order, with the same reasons, and times within 1 s. **Every scene has the same moves in the same order with the same reasons and targets** (8, 14, 8 and 23 moves). The times differ like this:

| Scene | Moves | Largest difference |
|---|---|---|
| `arenas` | 8 | 1.97 s (move 3, `activity`), 1.27 s (move 8, an approval). The others are within 0.64 s. |
| `many` | 14 | 0.77 s. |
| `follow` | 8 | 1.40 s (move 8, an approval), 1.27 s (move 6, an approval). The others are within 0.01 s. |
| `ten` | 23 | 1.27 s (moves 1 and 2, approvals). The others are within 0.77 s. |

Six moves differ by more than 1 s. Both reasons are about the events, not about the camera:

1. **Approvals come early by up to 1.4 s.** The exported `waiting_permission` is sent when the penguin starts to walk to the sign post (a walk of up to 1.5 s). The mockup's notice starts when the penguin has arrived. A real adapter also sends the request at once. The client is early and never late. The test names the moves (`KNOWN_DEVIATIONS`). Moving the event to the arrival would make the penguin walk to the forge first.
2. **Helper work counts as activity.** The client counts `subagent_start` and `subagent_end` as activity of the arena, because every event is activity. The mockup's camera has no event for its helper work. In `arenas` the helper of #2 ends at 14.6 s, so arena A is "not quiet" 2 s longer, and the move for the busy arena (move 3) comes at 18.60 s and not at 16.63 s.

The smaller differences (0.03 s) are the step of the clock: the mockup's events are at exact times, and the client handles them at the next step of 1/60 s. A finished turn comes up to 0.5 s early in the client (`done` is sent at the start of the walk to the stage, decision of phase G-4).

### The first performance run

`--benchmark=<scene>` plays a scene once in real time, with no status bar and no frame cap (the window policy is off), and writes `run.csv` and `run.camera.json`: one line for each frame (`t`, `frame_ms`, `process_ms`, `move`) and the moves of the camera. `frame_ms` is the time between two frames, as the engine says: it includes the wait for vsync. `process_ms` is the time of the client's own frame code (the simulation, the camera and the update of the view). It does not include what the engine does to draw afterwards. `--vsync=on|off` sets the vsync. The agents that were there before the clip arrive before the first frame, so a run has no frame of the preroll.

`tools/benchmark-report.mjs run.csv` finds the long moves (flies and scrolls that widen the view to 4 rooms across or more). It prints the count, the median, the 95th and 99th percentile, the worst frame and the share over 16.7 ms, for each window, for all windows together and for the whole scene. It checks the pass rule of the plan too (a proposal: at most 1% of the frames over 20 ms in each window, none over 33 ms, and the 99th percentile of the process time at most 8 ms). `benchmark-report.test.mjs` tests it on made-up data.

**The machine.** It is a fast machine, **not** the reference machine of the plan (a low-end laptop with 8 GB of memory). CPU: 11th Gen Intel Core i7-11800H (8 cores). GPU: NVIDIA GeForce RTX 3060 Laptop GPU, a discrete GPU (OpenGL 3.3, driver 621.14, Compatibility renderer). Windows 11. Godot 4.7.2. The window is 1440x810 (the viewport is 480x270, scale 3). Spike S-6 read a refresh rate of 360 Hz for the screen. I did not read it again. Other programs were open.

**Results with the code of this phase** (the scene `ten`, 157 agents, 40 arenas, 54 s, 8 long moves; milliseconds):

| | Frames | Median | p95 | p99 | Worst | Over 16.7 ms |
|---|---|---|---|---|---|---|
| vsync on, the 8 long moves | 1626 | 4.17 | 8.94 | 14.47 | 23.21 | 0.1% |
| vsync on, the whole scene | 12223 | 3.33 | 10.61 | 14.69 | 133.33 | 0.2% |
| vsync off, the 8 long moves | 1404 | 4.92 | 10.98 | 15.91 | 19.95 | 0.3% |
| vsync off, the whole scene | 10617 | 3.70 | 12.50 | 16.67 | 150.00 | 0.9% |

The process time of the client code in the long moves: median 0.84 ms, 99th percentile 3.51 ms, worst 7.11 ms (vsync on); 99th percentile 4.64 ms, worst 6.14 ms (vsync off). The windows (vsync on):

| Long move | Frames | Median | p95 | p99 | Worst | Over 16.7 ms |
|---|---|---|---|---|---|---|
| fly to Z at 4.4 s | 193 | 4.17 | 10.00 | 14.36 | 15.33 | 0.0% |
| fly to F at 9.4 s | 212 | 4.17 | 6.97 | 14.41 | 15.41 | 0.0% |
| fly to AM at 14.2 s | 210 | 4.50 | 10.00 | 14.72 | 15.07 | 0.0% |
| scroll to page 4 at 25.5 s | 212 | 3.70 | 4.99 | 10.42 | 10.42 | 0.0% |
| fly to AH at 31.5 s | 219 | 4.17 | 8.79 | 13.88 | 14.46 | 0.0% |
| fly to C at 35.4 s | 211 | 4.20 | 9.71 | 15.25 | 16.36 | 0.0% |
| fly to AN at 40.0 s | 186 | 5.56 | 10.32 | 18.07 | 23.21 | 1.1% |
| fly to K at 44.2 s | 183 | 5.00 | 8.79 | 14.48 | 15.50 | 0.0% |

The pass rule is met **on this machine**, with both settings. That says nothing about the reference laptop, and **I do not claim that the target is met there**. Also not measured: a 60 Hz screen (the frame times with vsync on are about 4 ms, so this screen is not at 60 Hz), the mockup in Chromium on this machine (item 4 of "Performance"), memory, CPU beside an agent, and a window that is not focused.

**The first run, before the far rooms were simple** (the same scene and machine): in the long moves the median frame took 20.27 ms with vsync on (p99 41.78, worst 48.34, 63.8% of the frames over 16.7 ms) and 19.79 ms with vsync off (p99 41.67, worst 56.21, 62.9% over). The process time was low (median 2.8 ms, p99 6.5 to 7.3 ms), so the time was in the drawing of the engine: up to 32 rooms in view, each with five glow ellipses (one rectangle for each row) and the shadows of its penguins. The rule "a far room is simple" (below a scale of 0.4: no glow, no effects, no shadows) brought the median in the long moves to about 4 ms. That is a change of the look in the widest views only. A room at a scale of 0.4 or more is drawn in full. The decision is the owner's if it should be a smaller or a larger step (`ArenaView.FAR_FROM`).

**The first frame is slow.** The longest frame of every run is the first one (133 to 150 ms): the engine's first use of the textures and of the nodes. The second frame takes about 20 to 33 ms. Not measured on the reference machine.

**The cost of the simulation alone.** `test_simulation_cost.gd` steps 157 agents headless, with the arena model and the camera. It prints the time and fails above 10 ms for a step (the limit of the plan). On this machine: 1.6 to 2.0 ms for a step of 157 agents in 40 arenas with the camera, each with a call at a station. For the real scene `ten` played from its timeline (3420 steps, with the events, the director and the camera): 1.9 to 2.0 ms a step on average, 4.2 ms at the 99th percentile, and 6.7 to 15.8 ms for the worst step after time 0 (it changed from run to run, and it was the highest when the whole test suite ran: a pause of the machine, not the simulation, so the test gates on the 99th percentile). The worst step of the 3 s before time 0 took 24 to 32 ms: the 150 agents arrive in one step, before the first frame. This is one step of 1/60 s, so at 60 frames a second the simulation costs about 12% of a core on this machine. That is more than the plan's budgets for the case beside an agent (2% to 5% of a core with 1 to 12 agents working). With 12 agents it is much less, and I did not measure it.

### Other decisions of phase G-5

* **`limit` is the `maxPenguins` of the plan.** The director keeps 12, and the view raises it to 200 (`Options.DEFAULT_PENGUIN_LIMIT`). It was 12 in phase G-4, and `test_options.gd` says 200 now. Ten pages of four arenas of four agents are 160 penguins.
* **The view has arenas by default** (4 in an arena, 600 s). A real session from the bridge with a fifth agent opens arena B and the camera moves there. `--arena-size=0` brings back the one room.
* **Keys.** `Tab`, `Esc`, `N` and the arrows go to the camera. `Esc` first closes the scene menu if it is open. `F` is the camera's. The status bar's "follow" field shows `camera.mode`. The G-4 keys (Space, `[`, `]`, R, D, C) did not change.
* **The `S-6` spike code stays** (`spikes/s6/`, `art/s6_support.gd`). G-5 does not use `s6_support.gd`: the mipmaps come from the import setting of the room PNGs. The owner may delete the spike.
* **The log of the camera in the view** is `camera.moves`. The benchmark writes it as JSON. Nothing else reads it yet.
* **A closed arena with a penguin that is walking out** loses the penguin at once (the room is removed). It closes 30 s after the last agent left, and the walk takes a few seconds, so this does not show.

### What was checked, and what was not

* Checked: `node tools/run-gut.mjs` (34 scripts, 360 tests, all pass), `node tools/check.mjs` (80 scripts, no warnings), `node --test` in `godot/` (124 tests, 123 pass, 1 skipped by an existing test), `node --test` in `tools/mockup-2d/` (38 pass) and in `bridge/` (45 pass). The incremental camera agrees with the golden data and with the batch port. The four scenes play from their timelines, and the client decides the same arenas and the same camera moves as the mockup (the times are in the table above). I looked at screenshots of a slide (arena A to B at 7.3 s of `arenas`), the ribbon (8.0 s of `arenas` and 15.7 s of `ten`, arena AM), the overview (31.5 s of `arenas`, 18.5 s of `ten`), a fly of the scene `many` (4.4 s and 4.5 s) and the long flies of `ten` with the page numbers (4.9 s, 5.2 s and 14.9 s). The pictures look right: the rooms are smooth when they are small, the gutter is there, the free place is dark, and the sign says ARENA B and ARENA AM. I did not put them next to stills of the mockup.
* Not checked: the reference laptop, a 60 Hz screen, macOS and Linux, a real session from the bridge with arenas (the scenes only), a window that has no focus while a long move plays, shimmer in a moving fly (I looked at still pictures), memory, and the cost beside an agent. The mockup was not run in Chromium for the baseline. The number "gold" of the page of the target in the fly screenshots is checked by a test, not by my eye: the numbers are small. The first frame of 133 to 150 ms was seen in every run and not explained further.

### Open questions (phase G-5)

1. **How far a room is "far".** Below a scale of 0.4 (2.5 rooms across) a room has no glow, no effects and no shadows. It made the long moves 5 times faster here. Is this look acceptable in the widest views, and in the overview of 16 rooms?
2. **Approvals come early.** The camera pulls at the request, and the mockup pulls when the penguin has arrived. Is the early pull wanted? (A real adapter sends the request at once.)
3. **Helper work counts as activity.** The mockup's camera does not count it. It changes when the busy-arena move comes. Keep it?
4. **The default of the view is arenas of 4, leaving after 600 s, and 200 penguins.** For a real session this changes the look of phase G-4 (a fifth agent opens a second room).
5. **The 133 to 150 ms first frame.** Does it matter? A loading screen or a warm-up of the first frame could hide it. Not measured on the reference machine.
6. **The simulation costs 2 ms a step in `ten`** (12% of a core at 60 steps a second on this machine). The plan's budgets for the case beside an agent are 2% to 5% for 1 to 12 agents. Is a step of the simulation at 30 per second without focus acceptable (the story would run in steps of 1/30 s)?
7. **The `S-6` spike code**: delete `spikes/s6/` and `art/s6_support.gd`, or keep them.

## Phase G-6: interface and log

The bar, the cards, the number chips, the focus ring and label, the approval notices, the ribbon of a finished turn, the tabs, the page boxes, the follow switch and its menu, the overview labels, the keys and the mouse. This phase also measures the start-up and the cost beside an agent, and cuts the cost.

```bash
"$GODOT" --path . -- --demo=arenas            # in godot/. The keys and the mouse are in "Keys and mouse" below
"$GODOT" --path . -- --demo=multi --frame-stats   # prints the average cost of a frame every 5 s
node tools/startup.mjs                         # the time to the first frame, five warm runs (needs a window)
node tools/cost.mjs --matrix --seconds 20      # CPU and memory in each state of the window (about 15 minutes)
```

### What was added

| File | Content |
|---|---|
| `src/core/log_model.gd` | The activity log and the cards, built from the events that the director also gets. No drawing, no clock. |
| `src/core/bar_layout.gd` | Where the tabs, the page boxes and their arrows, the follow switch, the menu, the cards and the overview cells lie, in the pixels of the 480x270 viewport. |
| `src/view/interface_model.gd` | Reads the director, the camera and the log and gives one Dictionary (`ui`) for each frame: what the bar shows, the tabs, the pages, the cards, the overview, the menu. It also does the hit tests. |
| `src/view/ui_input.gd` | Turns a hit into a call of the camera, and a key of the open follow menu into a change of what pulls the camera. |
| `src/core/startup_report.gd` | The times of the start-up (`--startup-report=<file>`). |
| `art/ui_kit.gd` | The colours of the log, the number chip, the outline, the dots of a running call, the status text of a card, the ring. |
| `art/crowd_art.gd` | What a room shows of its agents: chips, focus ring and tag, approval notices, the bubble of a penguin in a line, the ribbon of a finished turn. |
| `art/bar_art.gd` | The three kinds of bar (see below), the tabs, the page boxes, the follow switch. |
| `art/overview_art.gd` | The labels of the overview, the arrows at its edges, and the follow menu. |
| `art/status_art.gd` (changed) | No longer the stand-in bar. It draws the key cap of a paused or fast clock, a line for a problem, and the list of scenes. |
| `art/room_stage_art.gd`, `art/text_art.gd`, `art/draw_kit.gd` (changed) | The room draws the crowd data. `TextArt` has `fit` and `rich_width` and a cache of glyphs. `DrawKit.ellipse_rects` is fast (see "The cost"). |
| `src/core/director.gd`, `clock.gd`, `frame_policy.gd`, `options.gd` (changed) | The log model, the time at which an arena opened or closed, the agents that are not shown, coarse steps for a window that is not shown, the focus cap, new options. |
| `tools/ui_shots.gd`, `tools/startup.mjs`, `tools/cost.mjs`, `tools/load_scripts_probe.gd` | The screenshot tool of this phase, the start-up measurement, the cost measurement, and a probe of the time that the scripts need to load. |

### The log model

`LogModel` keeps, for each agent, the last lines with their state and the one card of the agent.

* A line: `{ icon, tool, target, state, id, error, thinking, detail }`. The state is `run` (a call that is open), `OK`, `FAIL`, `WAIT`, or `""` (a plain line).
* **Events.** `tool_start` makes a `run` line. `tool_end` closes the line with the same `id` (or the newest open one) as `OK` or `FAIL`, and a failure adds a red line with the error text. `waiting_permission` makes the open line `WAIT` (a request with no open call makes its own line). Any later event of the agent ends the wait: the line runs again, unless the event is the end of that call. `thinking` (or a tool of category `think`) makes a "Thinking" line that is only on the log while it lasts. `done` makes the "Turn complete" line with the calls, the helpers and the seconds of the turn. `error` makes a `FAIL` line. Any other type is a plain line with the `other` icon.
* **The card** has the state of the newest event: `run`, `OK`, `FAIL`, `WAIT` or `DONE`, with its icon and target. A failure stays on the card until the next event of the agent. The card keeps the icon of the call that waited ("ask") after the approval, as the mockup does.
* **Numbers.** The director gives each agent a number when it first appears, and it keeps it until the agent leaves. The model takes the number. A helper wears the number of its parent, adds to the "+N" on the parent's card, and makes no line and no change of the card with its own events (it only shows that its parent is busy).
* **Cards.** Full up to five agents of an arena (number, framework, session, icon, target, status), compact from six (number, short name, icon, status). `cards(arena)` gives them in the order of the numbers.
* **Counts.** Agents, helpers and calls. The top line of the one-arena bar uses them, and "X joined" shows for 2.2 s.
* **Long targets** are cleaned in the model (one line, runs of spaces made one, at most 160 characters) and cut to a width in the art with `TextArt.fit` (two dots at the end, as `fit` of the mockup does).
* **A short session id.** Ids of up to 6 characters stay. A longer one shows its last 4 characters. Random ids differ at the end, and the number is the real name.

### The bar

* **One agent in one arena: the log.** The last three lines with their icon, tool, target and state, and a panel with the link, the framework, the calls and the helpers (`hud` of the session scene). The room has no number chips and no ring then (the mockup's session scene has none): a plain tag says what the penguin does, and the red tag of a failure.
* **One arena, several agents: the top line and the cards.** The link, the counts (or "X joined"), the follow pill (AUTO or MANUAL; a click or F switches), and the focused agent. Then the cards.
* **Two arenas or more: the tabs and the page boxes.** The light of the link, the four tabs of a page (the letter on a plate in the rug colour, a chip for each agent or a pip when the chips do not fit, and the state: WAIT blinking gold, FAIL red, the running dots, DONE green, idle, empty with a dashed outline after a second), at most five page boxes round the page of the list with an arrow at each end that stands for the pages beyond (in the colour of the most urgent state there), the gold "+N" for agents that are not shown, and the follow switch (a mark for each kind that is ticked, gold while the pace holds a move back; the word MANUAL on blue). The cards of the arena on screen follow.
* **The overview.** The label of each arena (letter, chips, state) at full size over its room, "free" in a free place, an outline for the arena under the mouse (cream) or one that waits (gold, blinking), and an arrow at each edge that has pages beyond.
* **The cards of a hovered tab** show with the letter of that arena in front; the camera does not move. The cards of the overview are those of the hovered cell, or of the arena that the overview opened from.
* **The connection light** is green for a link that is open, gold while the client connects or reconnects, and red when the link has been down for 10 seconds or more. A scripted scene has no link: the light is green and the word is "demo" (the mockup says "online", which would not be true for a scripted scene).

### Keys and mouse

| Input | What happens |
|---|---|
| `F` | AUTO or MANUAL (a click on the pill in the one-arena bar does the same). |
| `Tab`, `Esc` | The overview on or off, leave it. |
| `Left`, `Right` | The previous or next arena, or page in the overview. |
| `N` | The arena that needs you. |
| `Space` | Pauses (demo mode only: a live view follows real time). |
| `1`, `2`, `3` | The speed of a demo: 1x, 2x, 4x, while the follow menu is closed. `[` and `]` change it too. |
| `R`, `D`, `C` | Start the scene again; the list of scenes; hide the bar. (Unchanged.) |
| Click a tab, a page box or arrow, a cell of the overview, an arrow at an edge of the overview | The camera moves there (MANUAL for a tab and a cell). |
| Click a card or a penguin (a helper counts for its parent) | The focus, in both modes. |
| Click the follow switch | Opens the menu. |
| In the open menu: `1` to `6`, `[`, `]`, `0`, `Esc`; or click a line, a pace arrow | Tick a kind, lower or raise the pace by one level (1 to 10 moves in 10 s, then no limit), manual only, close. A click elsewhere closes it and does nothing else. |
| Hover over a tab or a cell | Shows that arena's cards. |

All hit tests are in the 480x270 pixels of the viewport (`InterfaceModel.hit`). Input events in a real window arrive in window pixels, and the stretch mode turns them into viewport pixels before the view sees them. The pointer is a hand over anything that does a click.

### Decisions of phase G-6

The owner asked for these phases to run on their own. These are my choices. Each one can change.

1. **The bar by the number of agents.** One agent in one arena gets the log (three lines and the panel, as the mockup's session scene). Two agents or more in one arena get the top line and the cards. Two arenas or more get the tabs, the page boxes and the cards. So the bar changes its shape when a second agent arrives. The log shows more of one agent's work than one card can.
2. **Notices from the request.** The approval notice shows from the moment the request arrives (the card says WAIT at that moment too), not when the penguin has reached the sign post. The camera pulls at the request already (decision of phase G-5). The tail of the notice follows the penguin while it walks. After the answer the front notice is green ("APPROVED") for the 0.45 s of the penguin's small cheer.
3. **Stacked notices.** The oldest request is in front. At most four notices show behind it. The "+N" on the front one counts all the others.
4. **Number chips and the ring.** Every main penguin wears its number, and the focused one wears a tag with the number and what it does. A helper wears its parent's number, smaller. The focus ring is under the focused penguin (not when it flops, and not in a far room). A room with one agent has none of these (the mockup's session scene has none): a plain tag says what the penguin does.
5. **The finished-turn ribbon** ("TURN COMPLETE!" with the number, from 0.15 s to 3.2 s of the cheer) and the "..." bubble of a penguin in a line (after 0.2 s) are drawn now. The mockup has both. G-4 left them out.
6. **The light of the link and its words.** `online` (open), `connecting` (never open yet), `reconnecting` (it was open and dropped, less than 10 s ago), `offline` (10 s or more without a link), `demo` (a scripted scene). The time is wall-clock time, not the simulation clock, so a paused demo cannot hold it.
7. **The follow switch in the one-arena bar** is the pill with the word (AUTO or MANUAL), at the place of the mockup (x 214). A click on it does what F does. The switch with the marks and its menu belong to the bar with tabs, where the kinds of pull matter.
8. **Keys of demo mode.** Space, 1 to 3 and `[` `]` change the clock only in demo mode. A live view follows real time: pausing it would only make the events pile up. While the follow menu is open, 1 to 6, `[`, `]` and 0 are the menu's. Esc closes the menu first.
9. **A click while the menu is open** on anything but the menu closes it and does nothing else. The follow switch closes it too.
10. **An arrow of the page boxes** goes to the nearest page beyond it, and opens the overview there. The arrows at the edges of the overview scroll one page.
11. **The new arena's chip** shows in its tab and its card at the moment that the arena opens. The mockup shows the tab as "empty" until the penguin has popped in, 0.6 s later. A tab that says "empty" while an agent is already there would be wrong in a live view.
12. **The short session id.** Up to 6 characters as they are, else the last 4. The mockup's made-up ids are short.
13. **The hand cursor** over anything that a click does.
14. **Not drawn.** The mouse pointer and the key caps of the mockup's scripted demonstrations (a real person has a real pointer; the scenes' inputs go straight to the camera), the label above a helper (the mockup has "Explore the adapters" in its session scene; no event carries it), and the sound switch (phase G-7). A small key cap shows at the lower right while the clock is paused or runs at another speed: that is new, and it is the only sign of the pause now that the bar has no room for a word.
15. **`status_info()`** is still there for the tests and for a text view. The status art takes a smaller Dictionary.
16. **Frame cap with focus: 60.** See "The cost beside an agent". **A minimized window** runs at 4 frames a second with coarse steps.

### The screenshot pass

I took stills of every scene (`tools/shot.gd` for the 46 moments, `tools/ui_shots.gd` for the states that need a menu, a hover or the overview) at moments of the mockup's stills, put each next to the mockup's still of the same scene and time (`tools/mockup-2d/record.mjs --scene <name> --stills ...`, Chrome and Playwright outside the repository, see "Phase G-1" for the setup), and looked at the pairs at twice the size: `session` 3, 6.6, 12.5, 19.5 and 26 s; `multi` 3.5, 6.8, 9.5, 12.8, 17, 25 and 29.5 s; `arenas` 8, 10.5, 14, 16.3, 23.5, 26.8, 31.3, 34.5 and 37.9 s; `many` 4.5, 7, 14, 17.8, 23.5, 25.8, 31 and 47 s; `ten` 5.5, 9, 12, 14.9, 17.5, 22, 27, 31 and 41 s; `follow` 2.9, 9, 12, 17.5, 22, 27.5, 31 and 36.5 s. I looked at 17 of those pairs (the three kinds of bar, a flop, the notices, the compact cards, the overview of one page and of ten, a long fly with the page numbers, the menu with ticks and with the pace lowered, MANUAL), and at single stills of a hover, the overview with a hover, the menu in `ten`, a compact bar and the flop tag. The other 29 pairs were made and **not looked at**. I also looked at the link states (`live` scene: connecting, reconnecting, offline). The bar, the cards, the tabs and their states, the page boxes and arrows, the follow switch, the chips, the tags, the ring, the notices, the ribbon and the overview agree with the mockup in layout, colours and text. Where they differ:

| Difference | Why |
|---|---|
| The mockup has a mouse pointer, an outline round the hovered cell, and key caps (TAB, F) in its arena scenes | They are scripted demonstrations (decision 14). A hover and the outline work in the client (the hover shot shows the cards and the outline). |
| Our stills show a "PAUSED" key cap | The stills run with the clock paused. |
| The light says "demo" and not "online" | Decision 6. |
| Penguins and camera are at other places at some times (a slide that has arrived, a fly that is half done) | The timing differences of phase G-5 (the exported events, the actor's walking). The cards, the tabs and the notices follow the events, so they are in step with our penguins. |
| The one-agent room has a plain tag without the helper's tag, and no sparks at the forge at the same moments | Decision 14, and the same timing differences. |
| The "Task" line of the session scene says OK at 12.5 s, the mockup shows dots | The exported `tool_end` of the call that rings the bell comes when the penguin leaves the desk (phase G-4, decision 7). |
| The red tag says "Error: Exit code 1" where the mockup says "exit 1" | The client shows the text of the event. The made-up scene has that text. |
| The new arena's tab shows the chip at once (see decision 11) | Decision 11. |
| The mockup's text has a bold look in the bar and ours has thin strokes | Chrome draws the mockup's text with anti-aliasing; the client draws the glyph atlas (phase G-2, spike S-3). |

Mistakes that the pass found, now fixed: the card of a call that waited for an approval lost its icon after the call ended (it keeps "ask" now, as the mockup shows); the one-agent room showed a chip and a ring that the mockup's session scene does not have; the pause cap lay over the follow menu (the menu is over it now); and a tool's own argument (`--shots`) showed as a note in the room (`Options` knows the tool arguments now).

I did not compare pixel by pixel, and I did not look at every pair at full size.

### The tests of phase G-6

* `test_log_model.gd` (24): the lines and their states, a failure with its error, the end of a wait, thinking, the end of a turn, the last lines only, long targets, helpers, numbers, **cards full up to five agents and compact from six**, the order of the notices, the counts and the join notice, and the director feeding the model (an agent that leaves comes back with a new number).
* `test_bar_layout.gd`, `test_interface_model.gd` (23), `test_ui_input.gd`: the places, the three kinds of bar, the tabs and their states, the page boxes and the window of five, the "+N", the overview, a hover, the cards (also full and compact through the model), the follow menu, the pace levels, the state of the link, the hit tests (a penguin in front gets the click), and what each key and click does to the camera.
* `test_scripted_input.gd` (9): **the scripted input test.** The inputs of the scenes `arenas`, `follow`, `many` and `ten` (clicks on tabs, cells and page boxes, keys, and the lines of the follow menu) go through the real input path: `InputEventKey` and `InputEventMouseButton` at the place where the interface shows the thing, pushed into the viewport (`test/support/input_script.gd`), and the camera log must equal the log that the same scene gives when the timeline hands its inputs to the camera. It does: 8, 8, 14 and 23 moves, equal in target, reason and time. The same file checks a hover over a tab (the cards of that arena, the camera stays), a click on a card and on a penguin (the focus, in both modes), the menu opened by a click on the switch and driven by keys, that 1 to 3 are the speed only when the menu is closed, and that Space pauses only in demo mode. GUT's own panel is a tree of controls that takes the mouse before the unhandled stage, so the helper makes those controls ignore the mouse. A real window has no such panel.
* **The focus in both modes**: the existing `test_focus.gd` (hold, priority events, a click) and the camera parity tests, and here a click on a card or a penguin in AUTO and in MANUAL.
* `test_interface_art.gd`, `test_draw_kit.gd` (the fast ellipse against a test of every pixel, 375 ellipses), `test_startup_report.gd`, `tools/cost.test.mjs`: the data of the drawing, a drawing run of every kind of bar and room (an error would fail the run), the report of the start-up, the numbers of the two tools.
* A real mouse click in a real window: **checked by hand once.** With a PowerShell script (outside the repository) that moves the pointer to a place of the window and clicks, `--demo=arenas --log-events` printed `click at (137.0, 237.0) hit tab B` and `click at (459.0, 237.0) hit follow`. So the stretch mode gives viewport pixels to `_unhandled_input`. No automated test does this.

### The start-up

`node tools/startup.mjs` starts the client seven times (after one run to warm the cache) with `--startup-report=<file>`. It gives the time from the start of the process to the first drawn frame of the room (the system clock at the frame, minus the time at which the tool started the process). Machine: the fast one of the earlier phases (i7-11800H, RTX 3060 Laptop, Windows 11, a screen that runs at 60 Hz or more), Godot 4.7.2 **editor build, running from the source files**, warm cache, medians in milliseconds:

| | `multi` | `ten` |
|---|---|---|
| From the start of the process to the first frame of the room | **2236** (2151 to 2258) | **2559** (2541 to 2634) |
| Engine start to the start of the view's `_ready` | 1974 | 1954 |
| The `_ready` of the view (atlases 34, the scene, the agents that were there before) | 166 | 526 |
| End of `_ready` to the first drawn frame | 12 | 26 |

**The budget is 2 s. It is not met on this machine in this setup.** What the 2 s hold:

* **About 1.3 s is the engine.** An empty Godot project (one script, no scene content) needed 1.25 to 1.5 s from the start of the engine to its `_ready` on this machine.
* **About 0.7 to 0.9 s is the scripts.** `tools/load_scripts_probe.gd` (headless) loads the scripts that the main scene needs one after the other: 1.1 s in all before this phase's last changes, from 5 ms for a small file to 184 ms for `live_view.gd` (with what it reaches). GDScript is parsed and compiled at the first load. This phase added about 0.3 s of it (`interface_model`, `crowd_art`, `bar_art`, `overview_art`, `ui_kit`, `log_model`, `status_art`: 25 to 95 ms each). The warnings of the project do not matter (switched off, the load took the same time).
* The atlases take 34 ms, and the first drawn frame 12 to 26 ms.
* The scene `ten` needs 0.5 s for its `_ready`: 150 agents arrive in one step before the first frame (decision of phase G-5).

An **export** (compiled tokens, a release build of the engine) should be faster. I could not measure it: the export templates are not installed here (that is phase G-9). A start with a cold cache of the system and of the graphics driver was not measured. The reference laptop was not measured; it is slower.

**The 133 to 150 ms "first frame" of phase G-5 is explained.** It is not a slow frame. It is the `delta` that the engine gives to the first call of `_process`: 133 ms for `multi` and 143 ms for `ten`, whatever the length of `_ready` (169 ms and 597 ms). An empty project with a `_ready` that waits 400 ms gets 145 ms, and one that does nothing gets 22 to 36 ms. So the engine counts only part of a long `_ready` into the first delta. The frames that are drawn are short: the first one 12 to 26 ms after `_ready`, the second 2 to 7 ms.

### The cost beside an agent

`node tools/cost.mjs --matrix --seconds 20` starts the client (the window build of the editor) and, for scenarios `idle` (the bridge is up, one agent, no events), `replay` (the bridge replays the example Claude Code session again and again), `multi` (six agents), `arenas` (nine agents in three arenas) and `ten` (157 agents in 40 arenas), puts the window in each state and reads the CPU time and the working set of the process once a second for 20 s (after 8 s of start and 5 s for the state). CPU is in percent of **one** core (100 is one core). The tool checks the state in the client's log. **The state `unfocused` could not be reached for real in this run:** the system kept the foreground window and did not let the tool take it (it worked in other runs). The tool then starts the client with `--force-focus=false`, which makes the client behave as a window without the focus (the frame cap of 30 and the same drawing). Those rows are marked "forced". The system's own handling of a background window is not in them. `--log-events` was on in all runs, so each event is also written to the log file.

Machine: Intel Core i7-11800H (8 cores), NVIDIA GeForce RTX 3060 Laptop GPU (a discrete GPU), Windows 11, Godot 4.7.2 editor build, window of 1440x810. **This is not the reference machine** (a low-end laptop with 8 GB).

| Scenario | Focus (60 fps) | No focus (30 fps), forced | Minimized (4 fps, no drawing) | Memory |
|---|---|---|---|---|
| `idle`, 1 agent | 20.1 % | 10.0 % | 0.9 % | 229 MB |
| `replay`, 1 agent working | 21.1 % | 12.3 % | 5.9 % (see below) | 228 to 233 MB |
| `multi`, 6 agents | 25.7 % | 14.2 % | 0.5 % | 228 MB |
| `arenas`, 9 agents | 29.0 % | 15.2 % | 0.5 % | 228 MB |
| `ten`, 157 agents | 79.6 % (peak 100 %) | 45.1 % | 1.0 % | 250 MB |

The row `replay` minimized is probably high because each event of the replay is printed to the log (`--log-events`) and the replay runs without a pause between sessions; I did not run it again without the log.

**Before this phase's changes** (the first interface, measured once, `multi`): focus 100.1 % (no cap: this screen runs at 360 Hz and the client drew 160 to 360 frames a second), no focus 21.9 %, minimized 3.7 %. A baseline: an **empty Godot project** (one node) in the same editor build costs 6.4 % at 30 fps, 2.9 % at 10 fps, 193 MB. So the engine alone, here, is about 0.24 % of a core for each frame a second, and 190 MB.

**Against the budgets of the plan** (CPU: 2 % with 1 agent and 5 % with 12 agents, no focus, 30 fps; 0.5 % minimized; 200 MB with `multi`; start-up 2 s):

| Budget | Result on this machine | Met? |
|---|---|---|
| No focus, 1 agent working: 2 % | 10 to 12 % (the empty project at 30 fps: 6.4 %) | **No** |
| No focus, 12 agents working: 5 % | 14 to 15 % (6 and 9 agents; 12 were not run) | **No** |
| Minimized: 0.5 % | 0.5 to 1.0 % (0.9 % idle, 5.9 % with the replay and the log) | **At the limit**, not with the replay |
| Memory, `multi`: 200 MB | 228 MB (the empty project: 193 MB) | **No** |
| Time to the first frame: 2 s | 2.2 s | **No** |

The budgets are below what the engine itself costs in this build on this machine. The frame rate that the budgets name (30) costs 6.4 % for an empty window. I do not claim that any budget is met, and nothing here is the reference machine. A release export may cost less; this was not measured.

**What I changed to cut the cost** (the picture shows the same):

1. **A cap of 60 frames a second with focus** (`--focused-fps`, 0 for none). The simulation steps at 60 a second, and the picture only changes at a step, so a faster screen would show the same picture again and again. On this 360 Hz screen it was 100 % of a core, and it is 20 to 29 % now. (A screen at 60 Hz sees no change.)
2. **The ellipse in the draw code** (`DrawKit.ellipse_rects`) tested every pixel of the box round the shape in GDScript, in every frame. The glow of the forge alone is five ellipses. It works out the ends of each row from the equation now and checks them with the test of the definition, so the rectangles are the same (a test compares 375 ellipses with the old way, pixel by pixel). The drawing of the room went from 2.1 to 2.5 ms a frame to 0.6 to 0.9 ms.
3. **Glyph lookups are cached** (`TextArt`): a text was drawn with a formatted name and several dictionary lookups for each character, in every frame. The bar went from 0.5 to 1.3 ms to 0.2 to 0.6 ms.
4. **The status art** is told only when something changed, and the interface is not built when the bar is hidden.
5. **The interface model works out the label and the state of an arena only where it is needed** (the tabs of one page, the cells of the page in the overview, and one state for each arena for the page boxes), with a list of agents for each arena. In `ten` the building of the interface took 4.3 ms a frame and now takes about 1 ms.
6. **A minimized window** runs at 4 frames a second (it was 10), does not draw, counts a long frame as long as it lasts (up to 0.5 s) and moves the actors in pieces of six steps (`FramePolicy.COARSE_STEPS`). The clock, the events and the camera still run at every step. A test plays `multi` in coarse pieces and in fine steps: the same agents, helpers, camera moves, and all agents but at most one in the same phase of their story. 3.7 % became 0.5 % (`multi`).

**Not done**, and the next steps if the cost must go lower: draw only when the picture has changed (a calm room changes about ten times a second: the fire of the forge changes every 0.1 s); I tried Godot's low-processor mode on an empty project and a redraw made it cost 35 %, which I did not explain, so I did not use it; skip the looks and short effects of arenas that are not in view; export and measure a release build.

### The `ten` target with the interface drawn

`"$GODOT" --path . -- --benchmark=ten --benchmark-out=run.csv --vsync=on|off`, then `node tools/benchmark-report.mjs run.csv`. The interface (bar, tabs, page boxes, chips, labels) is drawn now. The window has no cap in a benchmark. Same machine, 54 s, 8 long moves, milliseconds:

| | Frames | Median | p95 | p99 | Worst | Over 16.7 ms |
|---|---|---|---|---|---|---|
| vsync on, the 8 long moves | 1072 | 7.41 | 9.47 | 11.46 | 12.57 | 0.0 % |
| vsync on, the whole scene | 8922 | 5.56 | 9.52 | 11.11 | 150.00 | 0.0 % |
| vsync off, the 8 long moves | 1058 | 7.47 | 9.40 | 12.44 | 17.50 | 0.1 % |
| vsync off, the whole scene | 8808 | 5.56 | 9.83 | 11.53 | 144.17 | 0.1 % |

The process time of the client code in the long moves: median 2.5 ms, 99th percentile 5.3 ms (vsync on) and 5.5 ms (off). The pass rule of the plan (a proposal) is **met on this machine with vsync on**. With vsync off it fails once: the 99th percentile of the process time in the fly to AM is 8.37 ms (limit 8). (An earlier run of this phase, before the interface model was made cheaper, failed the rule: the process time was 7 ms.) The worst frame of the whole scene is the first one (the engine's first delta, see above). The frames take about 7 ms now, against about 4 ms in phase G-5 (the interface, and the chips and tags of 4 to 16 rooms in a long move). **This says nothing about the reference laptop**, which I did not measure, and I do not claim that the target is met there.

### What was checked, and what was not

* Checked: `node tools/run-gut.mjs` (41 scripts, 458 tests, all pass; 41 is the number of `test_*.gd` files), `node --test` in `godot/` (134 tests, 133 pass, 1 skipped by an existing test), `node tools/check.mjs` (99 scripts, no warnings), `cd tools/mockup-2d && npm test` (38 pass) and `cd bridge && npm test` (45 pass). The scripted input test, the stills and the measurements above. A real click in a real window (once, by hand).
* Not checked: the reference laptop, a cold start, an export (compiled scripts, a release engine), macOS and Linux, a screen at 60 Hz (the frame times are from a faster screen), a real loss of focus in the cost runs (forced by an option), 12 agents working at once (6 and 9 were measured), a real session with the interface for a long time (memory over hours, the growth of the log), the look of the interface on a window of another size, shimmer in a moving fly, the 29 stills that I did not look at.
* A run of `cost.mjs` leaves no process behind when it ends. A run of my own that I started in the background without a way to stop it (the stats runs) did stay: look for stray `Godot_*` processes after a manual run.

### Open questions (phase G-6)

1. **The budgets of the plan.** They are below the cost of an empty project in this build here (2 % and 5 % at 30 fps against 6.4 %). What should they be, and on which machine and build? A release export would show what the engine costs without the editor.
2. **The start-up of 2 s.** About 1.3 s is the engine and about 0.8 s the scripts. Options: export and measure (compiled tokens may be much faster); show a first frame early (a small scene with the room's background) while the rest loads; fewer or lighter scripts. Which?
3. **The frame cap with focus: 60.** It halves the cost on screens above 60 Hz and changes nothing on a 60 Hz screen. A 120 or 144 Hz screen might look smoother in a camera move at 120 or 144. Keep 60?
4. **A minimized window runs the actors in coarse pieces** and reads the bridge 4 times a second (at most 64 events each time). Acceptable for a long session behind a window?
5. **Notices from the request** (decision 2) and **the bar that changes with the number of agents** (decision 1): keep?
6. **The mouse pointer and the key caps of the mockup's demonstrations** are not drawn. Does a recorded clip (phase G-8) need them? The mockup's clips have them.
7. **The `S-6` spike code** (`spikes/s6/`, `art/s6_support.gd`) is still there (open question 7 of phase G-5).


## Phase G-7: sound

The client plays the sound files of `art/sound/` (see "Sound files" above for how they were made). This phase adds the player side: the model that says which event plays which sound, the players, the master limiter, the sound switch with its menu, the keys and clicks, and a measurement of the memory and the CPU. **Nobody has listened to any of it.** The tests see that a player says it plays and that the level is held. They cannot say how it sounds. See "What was checked, and what was not".

```bash
cd godot
"$GODOT" --path . -- --demo=multi --sound=krakowiak     # start with a tune on (all sound is off without the option)
node tools/sound-levels.mjs                              # the levels of a tune and an event sound together
```

Keys: `M` turns all sound on or off. `S` opens the sound menu (or closes it). In the open menu `1` to `4` pick a tune (krakowiak, kujawiak, oberek, góralski), `0` picks no music, `E` turns the event sounds on or off, and `Esc` closes it. A click on the switch (top right) opens the menu, a click on a row picks it, and a click anywhere else closes the menu and does nothing else. Each change shows a short note under the switch for two seconds. `--sound=<tune>`, `--sound=on` or `--sound=events` starts with sound on. All sound starts off.

### What was added

| File | Content |
|---|---|
| `src/core/sound_model.gd` | The sound state (tune, event sounds, all sound), the keys and clicks of the switch, and the rules for which cue sounds. No audio call, no clock, no node. |
| `src/view/sound_player.gd` | One looping player for the tune and a pool of four for the event sounds, the master limiter, the loading and freeing of the files. It loads the files with `load()`. |
| `art/sound_ui_art.gd` | The sound switch and its menu, the places of both, and the hit test (compare `art/sound-ui.js` of the mockup). It starts with the copyright header. |
| `src/core/world.gd`, `penguin_actor.gd`, `director.gd` (changed) | The actors say when a sound is due (`World.add_sound`), and the director hands the cues on with the letter of their arena (`take_sound_cues`). Nothing is kept unless `record_sounds` is on. |
| `src/view/live_view.gd`, `src/core/options.gd` (changed) | The wiring: keys, mouse, the cues of each step, the pause, `--sound=`. |
| `tools/sound-levels.mjs` | The levels of a tune and an event sound together, from the files. |
| `tools/cost.mjs`, `tools/ui_shots.gd` (changed) | `--engine-arg=` for the cost tool (the dummy audio driver), and `sound=...` actions for the screenshot tool. |

### Which event plays which sound

The rules of the 2D view plan ("Sound", item 4) and `soundCues` of the mockup's `crowd.js`:

| Sound | When (on the simulation clock) |
|---|---|
| tink | At each hammer stroke at the workbench: every second frame of the hammer, 0.44 s apart. The same strokes that show a star. |
| bell | When a penguin hands work to a helper: once, at its first ring of the desk bell (not at each ring). |
| flop | When a call fails or an `error` event comes: at the start of the flop. |
| chime | When an agent starts to wait for approval: at the moment the actor takes the `waiting_permission` event, not when the penguin reaches the sign post. A second prompt while it waits makes no second chime. |
| fanfare | For a finished turn: 0.15 s after the cheer starts. |

A helper makes no sound (the mockup has cues for the agents only). The chime and the fanfare sound from every arena. The tink, bell and flop sound only from the arena that the camera rests on (`LiveView.rest_arena()`: the camera shows an arena and does not move). In the overview and during a move only the chime and the fanfare sound. The model drops a cue that is more than 0.5 s late (a window that was not shown, a long frame), merges two cues of one sound that are less than 0.05 s apart, and keeps at most 64 cues.

Nothing is collected while the event sounds are off: `Director.record_sounds` is on only while `SoundModel.events_playing()` is true, and the model drops what it is offered when sound is off.

### The players and what runs

* **Nothing exists while sound is off.** No player node, no stream in memory, no effect on the master bus. The view creates the players when sound turns on, and frees them when it turns off. A test checks all three.
* **A tune is loaded when it is chosen, and freed when another is chosen** (or when sound turns off, or when "no music" is chosen). A new tune starts from its beginning. The same tune chosen again goes on. The five event sounds (about 150 KB together) are loaded when sound turns on, and freed when the event sounds turn off.
* **The loop** comes from the `.import` files (`edit/loop_mode`, `edit/loop_end`, see "The import in Godot 4.7.2"). The player sets nothing. A test reads the loop mode of the loaded stream.
* **The pool** has four players. A sound that finds no free player is dropped, not queued.
* **The pause** of a demo (Space) pauses the tune and the event sounds. A live view cannot pause.
* **A window with no focus or a minimized window** keeps its sound. The cue rules are the same. (A person who does not want sound there turns it off with M.)

### The master limiter and the levels

Each file carries its own gentle limiter from the mockup's mixer (music gain 0.45, event gain 0.75). In the mockup one mixer limits the sum of the tune and the event sounds. In the client each file is separate, so two files can add up above full scale. `SoundPlayer` puts an `AudioEffectHardLimiter` on the master bus (ceiling -1 dBFS, release 0.1 s) when sound turns on, and takes it away when sound turns off. It sits in `src/view/` and not in `art/`, because it is a setting of the output and makes no sound: the license check names only `AudioStreamGenerator` and `AudioStreamWAV`, and the check passes.

`node tools/sound-levels.mjs` adds each tune to each event sound at every start time of the event (the tune wraps round, as a loop does) and reports the largest sample of the sum. It adds the samples as if both files had one rate (they differ by 0.1% at most), and it does not model the limiter. With the tune at 0 dB the worst case is oberek + flop: **+3.4 dBFS**, 2.9% of the start times above full scale. So the player plays the tune at **-3 dB** (`MUSIC_VOLUME_DB`). Then:

| Tune | Tune peak (-3 dB) | Worst sum with the loudest event (flop) | Start times above full scale | Start times above -1 dBFS |
|---|---|---|---|---|
| krakowiak | -7.0 dBFS | +1.1 dBFS | 0.3 % | 2.3 % |
| kujawiak | -8.3 dBFS | +0.7 dBFS | 0.0 % | 0.4 % |
| oberek | -4.8 dBFS | +1.9 dBFS | 0.7 % | 2.5 % |
| goralski | -8.6 dBFS | +0.3 dBFS | 0.0 % | 0.5 % |

The other event sounds stay below +0 dBFS (the bell of oberek reaches -0.5 dBFS). Over all 20 pairs the worst sum is **+1.9 dBFS** (oberek + flop, at 30.6 s of the tune), so the limiter must take at most 2.9 dB off for a few milliseconds to hold -1 dBFS. `test_sound_levels.gd` checks the files' own peaks (every file peaks at -1.8 dBFS or lower, and the loudest event sound is the flop at -3.1 dBFS), and it **measures the master bus itself** under the dummy audio driver: the tune and four flops that start in the same frame, read through an `AudioEffectCapture` after the limiter. Result: the peak is **2.910** of full scale without the limiter, and **0.891** (the ceiling) with it. The "-3 dB" is my choice and has not been judged by ear: the tune may now be too quiet, or the 1.9 dB of limiting at the worst moment may be audible.

What was not checked: more than one event sound together with a tune in the files' own timing (up to four can play at once; the bus test used four flops at once on top of a tune), the resampling of the engine, and how the limiter sounds.

### Memory and CPU

The same machine as the earlier phases (i7-11800H, RTX 3060 Laptop GPU, Windows 11, a window of 1440x810, Godot 4.7.2 editor build run from the source files; **not the reference laptop**). The scene is `multi` (6 agents), measured with `tools/cost.mjs` (CPU in percent of **one** core, memory is the working set of the process). Both columns run with `--audio-driver Dummy`; the right column also has `--sound=krakowiak` (a tune and the event sounds; the log of the client says `sound on ... player=true playing=true driver=Dummy`).

```bash
node tools/cost.mjs --scenario multi --state unfocused --seconds 30 --engine-arg=--audio-driver --engine-arg=Dummy --client-arg=--sound=krakowiak
```

| State of the window | Sound off | Tune and event sounds on |
|---|---|---|
| Focus (60 fps), one pair, 20 s | 24.5 % CPU, 227 MB | 30.8 % CPU, 232 MB |
| No focus (30 fps, forced by `--force-focus=false`), four runs each, 20 or 30 s | 15.8 % mean (15.4, 17.2, 17.3, 13.2), 229 to 230 MB | 13.0 % mean (12.3, 13.6, 12.5, 13.7), 229 to 233 MB |
| Minimized (4 fps, no drawing), 20 s | 0.8 % CPU, 230 MB | 0.4 % CPU, 232 MB |

A second set has no window and no drawing (`--headless`, the dummy driver, the scene `multi`, three runs of 25 s each, after 8 s of start), so that the audio is a larger part of what is measured:

| Sound | CPU, three runs | Mean | Memory |
|---|---|---|---|
| off | 0.6, 0.3, 0.3 % | 0.4 % | 121 MB |
| krakowiak and event sounds | 0.3, 0.7, 0.5 % | 0.5 % | 124 MB |
| kujawiak (the largest tune) and event sounds | 0.4, 0.4, 0.8 % | 0.5 % | 124 MB |
| event sounds only | 0.4, 0.3, 0.8 % | 0.5 % | 122 MB |

How to read it:

* **CPU: no cost that I can measure.** The runs with a window differ from each other by 4 points or more (the same setting gave 13.2 and 17.3 %), and the runs with sound are not higher than the runs without it (the one pair with focus shows +6.3 points, the runs without focus show the opposite). The headless runs, where the audio is a larger share, show about +0.1 point (0.4 to 0.5 %). So the audio (the mixing, the resampling of 22.05 kHz to the mix rate, the limiter; the files are PCM, so nothing is decoded) costs less than about 0.5 point of one core. The mixing thread runs at the pace of a real device (a capture on the master bus got 65536 frames in 1.5 s).
* **Memory: the tune.** The working set is 3 to 5 MB higher with a tune (krakowiak, 2.4 MB of samples) and about 1 MB higher with the event sounds only. `test_sound_player.gd` reads the engine's static memory: 3.0 MB more with kujawiak playing (the file is 3.0 MB), and it is gone again 0.3 s after sound is turned off. All four tunes are 9.9 MB, so a client that kept them all in memory would add 10 MB; it keeps one.
* **The budgets of the plan** are not changed by sound: the engine alone is above them (see "The cost beside an agent" in phase G-6), and sound adds under 0.5 point of CPU and at most 5 MB.
* **What is not in the numbers.** A real audio device: the runs use the dummy audio driver, so that a measurement does not play a tune through the speakers of whoever runs it. The cost of the output path of the operating system (on Windows the shared-mode audio engine and the device buffer) is not measured. A release export, the reference laptop, and a long run were not measured.

### Decisions of phase G-7

The owner asked for these phases to run on their own. These are my choices. Each one can change.

1. **Cues come from the actors,** into `World.sounds`, and the director gives them out with the letter of the arena. The model decides what sounds. This keeps the simulation free of audio and a run with no sound collects nothing.
2. **The bell sounds once** for each handing of work (the mockup does the same), and the chime sounds at the request, not at the sign post. The mockup's chime is at the time of the scripted `waiting` event, which is the request too.
3. **Picking a tune, or turning the event sounds on or off, turns all sound on** (as in the mockup). M turns all sound on or off and keeps the tune and the event setting.
4. **A click outside the open sound menu closes it and does nothing else.** The mockup lets the click go on to the page. Here it is the rule of the follow menu too (decision 9 of phase G-6). The sound menu and the follow menu are never open together: opening one closes the other. They would overlap (the sound menu reaches y 141, the follow menu starts at y 125).
5. **While the sound menu is open, 1 to 4 and 0 are its keys.** The speed keys 1 to 3 of a demo work only while the sound menu and the follow menu are closed. Esc closes the sound menu first. E works only while the menu is open, as in the mockup.
6. **The toast** shows for two seconds of wall-clock time, and only while the menu is closed (as in the mockup). Its words: `music: <name>` (or `off`), `event sounds: on|off`, `all sound on|off   (M)`.
7. **The switch is always drawn,** also with the bar hidden (C) or with `--clean`. The mockup's recordings show it too (`?sound=on`). Phase G-8 may decide to hide it in clips.
8. **The tune plays at -3 dB** and the master bus has a hard limiter at -1 dBFS. See "The master limiter and the levels".
9. **The limiter is in `src/view/`,** and not in `art/`. The license check allows it. It exists only while sound is on.
10. **22.05 kHz files are played as they are.** The engine resamples them to its mix rate.
11. **`--sound=` is a start-up option** (`on`, `events`, `off` or a tune name). The default is all sound off. It exists for measurements and for a person who always wants sound; it is not a setting that is kept.
12. **The cost runs use the dummy audio driver** (`--audio-driver Dummy`), so that a measurement does not play a tune through the speakers of whoever runs it. The engine still decodes and mixes. The part of the cost that is the operating system's audio output is not in the numbers.

### The tests of phase G-7

* `test_sound_model.gd` (43): the state and its changes, the toast, every key, every click, the hover, and every rule for the cues: nothing sounds while sound is off or the event sounds are off, each cue gives its sound, the sounds of one arena only from the arena the camera rests on and not while it moves or shows the overview, the chime and the fanfare from every arena, the order, the late cue, the double cue, the limit, and the new session.
* `test_sound_cues.gd` (13): the actors' cues on the clock: tink spacing and first stroke, one bell, flop for a failure and for an error, the chime at the request and once, the fanfare 0.15 s after the cheer starts, a silent helper, the letters of the arenas, and the model with the cues of a two-arena run.
* `test_sound_player.gd` (16, dummy audio driver): nothing exists while sound is off; every tune loads, plays and loops; every event sound loads, plays and stops; the pool; turning sound off frees the players, the limiter and the tune; a tune is freed when another is chosen; a new tune starts at its beginning; the limiter is on the master bus once; the pause; and the memory of a tune (3.0 MB on, gone when sound is off).
* `test_sound_levels.gd` (3): the peaks of the files, the sum of the largest peaks, and the **master bus peak with and without the limiter** (about 3 s of real time, because the dummy driver mixes at the pace of a real device).
* `test_sound_input.gd` (22): through the real input path (`InputEventKey` and `InputEventMouseButton` pushed into the viewport): sound starts off and nothing exists; a run with no sound collects no cue; M turns sound on and off (players, limiter, cue recording follow); S, the digits, E and Esc; 1 to 3 are the demo speed only while both menus are closed; the follow menu keeps its keys; the two menus are never open together; clicks on the switch, a row, and elsewhere; the hover; the cues of a scene reach the players; the pause; the places and the hit tests of the switch (every pixel edge of the menu and of a row); `góralski` is in the glyph atlas; the switch draws in every state; the toast comes and goes.
* `tools/sound-levels.test.mjs` (6): the search for the worst start time on made-up signals (against a plain search), the numbers of the tool against the player's constants, the names against the model, and the levels of the real files.

### What was checked, and what was not

* Checked: `node tools/run-gut.mjs` (46 scripts, 555 tests, all pass; 46 is the number of `test_*.gd` files), `node --test` in `godot/` (140 tests, 139 pass, 1 skipped by an existing test; it includes the license check and the manifest check of the sound files), `node tools/check.mjs` (107 scripts, no warnings), `cd tools/mockup-2d && node --test` (38 pass) and `cd bridge && node --test` (45 pass). (`npm test` in the last two is `node --test`; I ran it directly because `npm` uses the old Node on this machine.) The bridge needed `npm ci` once in the new worktree. The mockup, the schema, the bridge and the adapters did not change.
* Checked by looking: stills of the switch (off, on, menu open, hover on a row, events off, the toast) at 5 to 8 times the size, made with `tools/ui_shots.gd`. The real app (`--demo=multi --sound=krakowiak --audio-driver Dummy`) started with the players running.
* **Not checked: how anything sounds.** Nobody has listened to a tune, the join of a loop, an event sound, the 22.05 kHz files, the -3 dB of the tune, or the limiter at work. I cannot listen. The plan's exit check "a person listens to all four tunes and the five sounds" is **still open**.
* Not run: `node tools/render-sound.mjs --check` (it needs Chromium; the sound files did not change, and the manifest check passed).
* Not checked: a real audio device (the tests and the cost runs use the dummy driver; no sound was played through speakers), a tune together with several event sounds in their own timing, the output latency, a long listening session (memory over hours), macOS and Linux, a release export, the reference laptop.

### Open questions (phase G-7)

1. **Listening.** Someone must listen to the four tunes, the five sounds, the join of each loop, the limiter at the worst moment, and decide: 22.05 kHz or 44.1 kHz (the size would double), -3 dB for the tune or another level.
2. **Sound while the window has no focus or is minimized.** It plays now. Should the tune stop when the window is minimized?
3. **The clicks.** A click outside the sound menu only closes it (the mockup also lets it go on). Keep?
4. **The switch in clips.** The mockup shows it in recordings. Should clips (phase G-8) show it?
5. **The sound clock.** The plan's open question 3 stands: the client does not follow the audio clock. The sounds start from the simulation clock, so they are late by the output latency. Not measured.


## Phase G-8: replay, recording and the tour

This phase adds three things. The client can record a scene as a clip, with the same frames and the same sound on every run of one machine. The scene `tour` plays in the client. And a session that is replayed through the bridge is checked in the real client. It also settles spike S-5 (Movie Maker).

```bash
cd godot
node tools/record.mjs --scene tour                      # out/tour.mp4: 1920x1080, 30 fps, sound (needs a window and ffmpeg)
node tools/record.mjs --scene multi --stills 3.5,9.5    # out/still-multi-3.5.png and out/still-multi-9.5.png (480x270)
node tools/determinism.mjs --scene session              # records twice and compares every frame and the WAV file
"$GODOT" --path . -- --demo=tour                        # the tour in a window (Space pauses, 1 to 3 set the speed)

# the Linux recorder (from the root of the repository; Docker or Podman)
docker build -f godot/tools/Dockerfile -t agent-workshop-godot-recorder .
docker run --rm --init -v "$PWD/godot/out:/app/godot/out" agent-workshop-godot-recorder --scene tour
```

`tools/record.mjs` keeps the options of the mockup's recorder: `--scene` (`session` by default, `multi`, `arenas`, `many`, `follow`, `ten`, `tour`), `--fps` (30), `--out`, `--stills <seconds,...>`, `--music <tune>|off`, `--events 0`, `--silent`, `--reduced` and `--menu <seconds>`. It adds `--no-switch` (do not draw the sound switch), `--keep-frames` and `--godot-arg`. The files go to `godot/out/`, which git ignores. A recording needs a real window. It does not run with `--headless`. With `--fps` the tool accepts only rates that divide 48000 (24, 25, 30, 48, 60): see "Spike S-5". If ffmpeg is not on the `PATH` (or in `FFMPEG`), the tool says so, keeps the frames and the WAV file in `out/<scene>.frames/`, and writes the command to `out/<scene>.mp4.ffmpeg.txt`.

### Spike S-5: Movie Maker, run on 2026-11-16

**Question:** does Godot's Movie Maker mode (`--write-movie`, `--fixed-fps`) run here, write a PNG sequence and a WAV file, and give the same files on two runs? **Answer: yes, on this machine and in the Linux container. The check is in the table.**

| What | Result |
|---|---|
| Does it run in a real window? | Yes. Windows 11, Godot 4.7.2 (editor console build), OpenGL (Compatibility renderer), an NVIDIA RTX 3060 Laptop GPU. `--write-movie out/t.png --fixed-fps 30` wrote `t00000000.png`, `t00000001.png`, ... and `t.wav`, and exited at `--quit-after`. It ran at 2 times real time for a 480x270 scene. |
| The size of a frame | **480x270**, not the size of the window. The project has `stretch/mode = viewport`, so Movie Maker saves the viewport. ffmpeg makes the 4x scale, with `flags=neighbor`. |
| The sound file | PCM, 32 bit, **stereo, 48000 Hz** (the project setting `editor/movie_writer/mix_rate`). 90 frames at 30 fps (3 s) gave 144000 sample frames of two channels: 1600 for each video frame. |
| Does the mix rate need to divide by the frame rate? | The engine takes `mix_rate / fps` samples for each frame, so it must be a whole number: that is the rule in the documentation, and `record.mjs` keeps to it (24, 25, 30, 48 and 60 work out). The seven scenes were recorded at 30 fps, and one clip at 25 fps (in the container; 1250 frames for 50 s). |
| Do the sound players of phase G-7 play inside it? | Yes. With `--sound=krakowiak` the WAV file of `multi` has a tune at -22 dB RMS, and the event sounds show as peaks (a bell at 7 s: -18 dB for that second). Movie Maker replaces the audio driver with its own dummy driver and mixes the sound frame by frame. The files and the players are the same as in play. |
| Same on two runs? | **Yes.** `multi` (300 frames and the tune), 300 PNG files and the WAV file: all hashes equal. The full results are in "The same frames on every run". |
| Under Xvfb and a software renderer (Linux)? | **Yes**, in the container of this phase: Debian, Xvfb, Mesa llvmpipe. See "The Linux recorder". |

How the sound reaches the clip: `SoundPlayer` starts the tune when the client starts. The first frame starts the mixing, so the tune starts at the first frame. An event sound starts in the step in which its cue is due. Godot mixes it in the frame in which `play()` was called. So an event sound is on the frame at or after its time, and at most one frame late (33 ms at 30 fps). The picture and the sound of a clip come from the same frame, so they stay together.

### What was added

| File | Content |
|---|---|
| `src/core/recording.gd` | The pure parts of recording: the number of frames of a clip (`ceil(duration * fps)`), the simulation step that frame `i` shows, the scripted pointer (`cursorAt` of the mockup), the key caps, the open windows of the follow menu, and the check for two penguins on one spot. |
| `src/core/tour.gd` | The tour: the stops of the scene file, and the map from the clip time to the scene time (the clip clock goes on during a stop, the scene clock stands still). |
| `src/view/tour_holes.gd` | Works out the lit parts of a stop from the live scene (the penguins, the cards, the helper). |
| `art/tour_art.gd` | The dim screen, the lit parts with their dashed outline, and the callouts (port of `art/tour-art.js`). Art: it has the header. |
| `art/pointer_art.gd` | The mouse pointer with its click ring, and the key caps (`drawCursor` of `crowd-art.js` and `keycaps` of `arenas-art.js`). Art. |
| `src/core/trace_log.gd` | The label of what a penguin does, as the behaviour trace fixture writes it. The option `--trace` prints it. The test helper `test/support/trace.gd` uses it too. |
| `src/view/live_view.gd`, `src/core/options.gd`, `src/net/timeline_player.gd`, `src/view/arena_view.gd`, `src/view/interface_model.gd` (changed) | Recording mode, the scripted pointer and keys, the tour, the empty room at the start, the options `--record-fps`, `--stills`, `--stills-out`, `--menu`, `--events=0`, `--no-switch`, `--trace`. |
| `src/core/penguin_actor.gd` (changed) | A penguin keeps its spot while it lies after a failure and while it cheers after an approval (see decision 12). |
| `tools/record.mjs`, `tools/determinism.mjs` | The recorder and the check that two runs agree. |
| `tools/Dockerfile`, `tools/Dockerfile.dockerignore` | The Linux recorder. |
| `tools/export-scenes.mjs` (changed) | The scene files carry `paths`, `keys` and `menus`. It makes `demo/tour.json`. |
| `demo/tour.json` | The scene `tour`: 43 events and 31 stops. The six other files have the new fields too. |
| `test/test_recording.gd`, `test/test_tour.gd`, `tools/record.test.mjs`, `tools/replay.test.mjs` | The tests of this phase. |

### How a recording works

1. `record.mjs` starts Godot with `--write-movie <folder>/f.png --fixed-fps <fps>` and, after `--`, `--demo=<scene> --record-fps=<fps> --sound=<tune>`.
2. The client plays the scene in recording mode. Movie Maker calls `_process` once for each frame, with a fixed time. Frame `i` shows the story at the time `i / fps`: the view runs the simulation (steps of 1/60 s) up to `floor(i * 60 / fps)` steps and draws. So a clip at 30 fps and live play at 144 fps show the same story, at the same moments.
3. The client counts the frames (`ceil(duration * fps)`, the mockup recorder's count) and quits after the last one. It prints `[record] scene=... frames=...` and, at the end, `[record] done frames=... conflicts=...`. The tool checks that Godot wrote exactly that number of PNG files.
4. The tool joins the PNG files and the WAV file: `ffmpeg -framerate 30 -i f%08d.png -i f.wav -vf scale=1920:1080:flags=neighbor -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -c:a aac -b:a 160k -shortest -movflags +faststart`. The options are those of the mockup recorder.
5. `--stills 7,22.5` runs the client without Movie Maker. It runs the simulation with no drawing up to each time, draws one frame, waits for it, and saves the 480x270 viewport as `still-<n>.png`. The tool renames the files to `still-<scene>-<seconds>.png`, as the mockup recorder does.
6. The check for two penguins on one spot runs at every frame. The client prints each case (`[record] conflict ...`). The tool then fails with the list, and so does the client's exit code.

### Decisions of phase G-8

The owner asked for these phases to run on their own. These are my choices. Each one can change.

1. **Movie Maker is the way to render fixed-step frames.** It runs here, so no other way was needed.
2. **Frame `i` is the time `i / fps`,** and the first frame shows time 0 (the clock does not run before it). The mockup recorder does the same. An event at exactly time 0 shows in the second frame.
3. **Recording mode** is `--record-fps=<n>` (or `--stills=...`). It turns off: the window policy (no frame cap, no minimized state), the keys and the mouse, the wall clock (the toast of the sound switch uses the clip time), and the restart of a scene at its end. The client quits after the last frame.
4. **The sound switch is drawn in a clip** with the state of the options (on, a tune, no events, off with `--silent`), as the mockup's clips show it and as the tour explains it. The keys and the mouse cannot change it. `--no-switch` hides it. The owner can decide that clips do not show it (open question 1).
5. **The mouse pointer and the key caps of the scripted scenes** are drawn in recording mode and in demo mode. A recording has no person, so the scene's own path moves the pointer, and its clicks make a gold ring. In a recording the pointer also sets the hover point of the interface, so a hover over a tab shows that arena's cards, as in the mockup. In demo mode in a window, the real mouse keeps the hover. The follow menu of the scene `follow` opens and closes at the times that the script gives (`menus`).
6. **The scene files carry `paths`, `keys` and `menus`** (made by `export-scenes.mjs` from the mockup's scenes: `S.paths`, `S.keys`, `S.menus`, and the path of the pointer in `multi-agent.js`). The first scene file now has these fields too, empty where the mockup scripts nothing.
7. **The tour keeps the mockup's words, times and fixed rectangles.** The mockup works out the lit parts from its scripted penguins. The client has live penguins, so `tour.json` says what to light (`{agent: 1}`, `{card: 1}`, `{helper: 1}`, `{near: 3, ell: [...]}`, or a fixed `rect` or `ell`), and `tour_holes.gd` works out the places at the start of the stop. The scene stands still during a stop, so they do not change. `export-scenes.mjs` runs a copy of `tour.js` with four small changes: the helpers of the lit parts, one stop for the penguin that has the focus, one stop for the penguin that thinks in place, and a hand-over of the stops. It fails when the text of `tour.js` is not the text that it expects.
8. **The tour shows the top line and the cards from the first agent on** (the option `bar: "cards"` of the scene file), as the mockup's tour does. The client's rule for one agent is the log. The tour needs the bar that it explains.
9. **A room that waits for its first agent shows the empty room.** Before this phase it showed nothing until the first agent arrived. The mockup opens arena A at time 0, and the tour and the first frames of every scene show it empty.
10. **The tour in a window** runs the clip clock on the frame time. Space pauses it and 1 to 3 set its speed. At its end it waits 2.5 s and starts again. Its clip is 281.975 s long (the story is 47.904 s and the 31 stops are 234.071 s). The mockup says about 4.7 minutes.
11. **A scene's length in frames** is `ceil(duration * fps)`, where `duration` is the length of the scene file (the tour: the story and all stops).
12. **The check for two penguins on one spot found two real cases, and I fixed both.** (1) A penguin that fails a call lies down on its spot. The spot was free at once, so the next penguin of the line walked onto the penguin that lay there (the scene `multi`, 13 s). (2) A penguin whose approval came makes a small cheer at the sign post. The spot was free at once, and the next penguin that asked for an approval stood on it (`multi`, 20 s). Now the penguin keeps its spot until the flop (1.8 s) or the cheer (0.45 s) is over (`hold_spot`). The behaviour trace of the real Claude Code example is the same. The trace of the scene `multi` changed in one place: agent 5 now waits in the line at the forge while agent 3 lies there (`test/fixtures/expected-trace.json`). After the change the seven scenes have no case.
13. **A penguin that thinks where it stands is not counted.** It has no spot (decision 4 of phase G-4). But it can stand on the place of the station that it has just left, where the next penguin now works. The check ignores this, and in `many`, `follow` and `ten` it happens (189 distinct cases in `ten` when it is counted). That is a picture, not a rule of the stations: see open question 2.
14. **`--fps` must divide 48000.** The tool gives an error for other rates.
15. **`godot/out/` has a `.gdignore`** (the tool writes it). Without it Godot imports every frame the next time that it scans the project. The license check skips a folder named `out`.
16. **The Linux recorder is a Docker image** (decision of the plan: "the container"). It copies `godot/` into the image, downloads Godot at the pinned version with the script that checks the hash, and runs `record.mjs` under `xvfb-run`. See "The Linux recorder".
17. **`--trace`** prints `[trace] <who>: <station>`. `tools/replay.test.mjs` reads it. It does not change what the client does.

### The same frames on every run

`node tools/determinism.mjs --scene <name>` records a scene twice with the same options (the tune krakowiak and the event sounds), hashes every PNG file and the WAV file with SHA-256, and compares. Results, on this machine (Windows 11, Godot 4.7.2 editor build, NVIDIA RTX 3060 Laptop GPU, OpenGL), two runs one after the other:

| Scene | Frames | Frames that differ | WAV file (SHA-256, first 12 characters) | Result |
|---|---|---|---|---|
| `session` | 855 | 0 | `acb19f22167a` | same |
| `multi` | 915 | 0 | `9204c9745d66` | same |
| `arenas` | 1290 | 0 | `dbfb81f257c9` | same |
| `many` | 1590 | 0 | `207e506efc1a` | same |
| `follow` | 1500 | 0 | `29648cc2f2cc` | same |
| `ten` | 1620 | 0 | `f6f510585e63` | same |
| `tour` | 8460 | 0 | `0bc27251c53d` | same |

**What it covers:** this machine, this Godot build, this GPU and driver, the two runs of one session of the tool, the tune and the event sounds on. Every frame and the sound file are equal, scene by scene.

**What it does not cover:** another machine, another GPU, another operating system.

* A frame from the Windows run and the frame at the same time from the Linux container (Mesa llvmpipe) are **not equal**. About 1000 to 2000 pixels of a frame differ, by one level of one channel. The cause is the blending of the glows (the transparent ellipses of the forge and the lamp).
* The sound files of the two systems are equal. `session` has the same SHA-256 on both.
* The container gives the same frames again and again (`session`, two runs, equal).
* So clips for the repository should come from the container. Clips from different machines are not equal to the last bit.
* A change of the Godot build, of the driver, or of the pictures may change the frames too.
* The first run after a restart of the machine (a cold start) was not tried on its own.

### The Linux recorder

`tools/Dockerfile` (a Debian image with Node 24, Xvfb, Mesa's software renderer, ffmpeg, and Godot at the pinned version). The Docker of this machine was used.

* `docker build -f godot/tools/Dockerfile -t agent-workshop-godot-recorder .` worked. The Godot archive came from `downloads.godotengine.org`, and `get-godot.mjs` checked its SHA-512 hash (it matched). The image is 362 MB (content), 1.27 GB on disk.
* `docker run ... --scene session --stills 3,12.5,26` wrote three stills in 3 s. `--scene session` wrote a 1920x1080 H.264 clip with 855 frames, 28.5 s, AAC 48 kHz stereo (mean volume -22.3 dB, peak -2.1 dB), in 25 s.
* `docker run --entrypoint xvfb-run ... node tools/determinism.mjs --scene session` gave "same": 855 frames equal, WAV equal.
* The container makes the clips of the whole repository only if the owner wants them from Linux. Nothing was published.
* **Not tried:** Podman, an ARM host, a real Linux host with its own GPU driver, and a Windows container.
* **Not tried:** a run as another user. On a Linux host the clips belong to root unless `--user` is set.
* **Not tried:** the other six scenes with the default options in the container. They ran on Windows, see below. `follow` ran in the container with `--fps 25 --music oberek --menu 3 --reduced`: it wrote 1250 frames, 50 s, and the first seconds show the sound menu open with oberek ticked.

### The seven scenes recorded

Each scene was recorded once with `node tools/record.mjs --scene <name>` on Windows (default options: 30 fps, the tune krakowiak with the event sounds). The frames went to `out/<scene>.frames/`. **ffmpeg is not installed on this machine**, so the encoding used the ffmpeg of the container image of this phase, with the same arguments as `record.mjs` (the file `out/<scene>.mp4.ffmpeg.txt` that the tool writes). The clips are in the git-ignored `godot/out/`. None is committed.

| Scene | Scene file | Frames | Clip length | Size of the clip | Spot cases | Encoded and checked with ffprobe |
|---|---|---|---|---|---|---|
| `session` | 28.474 s | 855 | 28.5 s | 1.2 MB | 0 | 1920x1080 H.264, AAC, 855 frames |
| `multi` | 30.5 s | 915 | 30.5 s | 1.9 MB | 0 | 915 frames |
| `arenas` | 43 s | 1290 | 43.0 s | 3.8 MB | 0 | 1290 frames |
| `many` | 53 s | 1590 | 53.0 s | 12.5 MB | 0 | 1590 frames |
| `follow` | 50 s | 1500 | 50.0 s | 9.5 MB | 0 | 1500 frames |
| `ten` | 54 s | 1620 | 54.0 s | 17.6 MB | 0 | 1620 frames |
| `tour` | 47.904 s of story and 31 stops of 234.071 s in all | 8460 | 282.0 s (281.975 s) | 17.4 MB | 0 | 8460 frames |

All seven runs gave no case of two penguins on one spot. The expected length is `ceil(duration * 30) / 30` for a scene file of `duration` seconds. Every clip has that length and that number of frames (`ffprobe`), 1920x1080, H.264 and AAC.

**Stills I looked at** (made from the recorded frames, at 2 times the size):

* `session` at 19.5 s: the log bar, a helper at the telescope.
* `multi` at 23.9 s: six agents, the pointer on card 4, MANUAL, a ribbon and confetti.
* `arenas` at 31 s: the overview of three arenas and the TAB key cap.
* `many` at 19 s: the overview of nine arenas on two pages, and the RIGHT key cap.
* `follow` at 17 s: the follow menu open, with the pointer on "new arenas".
* `ten` at 26 s: a fly over the pages, the page numbers and the pointer.
* `tour`: 22 of the 31 stops. I saw the title card, the lit room, the stations with their penguin and callout, a flop, the helper, the sign post, the finished turn, four agents, the focus, two approvals and the last card.

The bar, the cards and the room are those of the earlier phases. New here are the pointer, the key caps, the menu of `follow` and the tour. They look as they do in the mockup. I did not put them next to the mockup's clips pixel by pixel.

### Replay through the bridge

* **`tools/replay.test.mjs`** (a Node test). It starts a real bridge on a free port. It runs the real client headless (`--headless --trace --log-events`) and waits until the bridge reports one client. Then it runs the replay command of the bridge on the real Claude Code example, at `--speed 0` and again at `--speed 4`. The command is `node src/cli.js replay ../schema/examples/claude-code-transcript.jsonl`: this is what `npm run replay` runs. The test reads the `[trace]` lines. In both runs the penguin visited: **Thinking chair, Map table, Bookshelf, Workbench, Forge, flop, Helper desk, Telescope, celebration.** That is the order of `claude-code-fixture` in `test/fixtures/expected-trace.json` (the same example through the adapter, at its real times). The two runs take about 13 s each. The helper vanishes before it reaches the telescope in a replay (its `subagent_end` comes within a second), so the test does not demand a helper trace.
* **The real client with a window** (the editor build, a window of 1440x810) against `npm run replay` at `--speed 4`, on this machine. I took eight screenshots of the window with a PowerShell script outside the repository, and I looked at them.
  1. The first one shows the empty room, the text "waiting for agent activity" and the light "online".
  2. Then a penguin walks in and works. The log lists Grep, Read and Edit, each with OK.
  3. A Bash call fails: FAIL shows in red. A Task call and a WebSearch call follow.
  4. The penguin goes to the telescope, and then to the stage. It celebrates with confetti. The log says "Turn complete, 6 calls, 1 helper".
  5. At the end it walks back to the rug.

  The picture and the order agree with the test.

### What was checked, and what was not

* **Checked:** `node tools/run-gut.mjs`, `node --test` in `godot/`, `node tools/check.mjs`, `cd tools/mockup-2d && node --test` and `cd bridge && node --test`: see the numbers in "Numbers of the last run" below. The seven recordings, the determinism runs, the container, the replay test and the window run, as written above.
* **Not checked: how a clip sounds.** I cannot listen. I checked that the WAV file holds the tune and the event sounds (levels and peaks), and that its hash is the same on Windows and Linux.
* **Not checked: other machines.** No other GPU, no real Linux host, no macOS, no Podman, no cold start.
* **Not checked: other options.** One clip was recorded with `--fps 25 --music oberek --menu 3 --reduced` (the scene `follow`, in the container). `--fps 24`, `48` and `60`, `--music off`, `--events 0`, `--silent` and `--no-switch` were tested as arguments only.
* **Not checked: the tour by a person.** Its frame loop in a window is tested, and I looked at stills of its stops. I did not look at every stop at full size. I did not compare it with the mockup's own clip pixel by pixel.

### Numbers of the last run

Run on 2026-11-16, Windows 11, Node 24 (from VS Code's Electron), Godot 4.7.2:

* `node tools/run-gut.mjs`: **48 scripts, 609 tests, all pass.** 48 is the number of `test_*.gd` files. The new scripts are `test_recording.gd` and `test_tour.gd`. `test_penguin_actor.gd` has two tests more (the spot of a penguin that lies, and the spot at the sign post).
* `node --test` in `godot/`: **171 tests, 170 pass, 0 fail, 1 skipped** (the skip is older). It includes `tools/record.test.mjs`, `tools/replay.test.mjs`, the license check, and the checks of the scene files.
* `node tools/check.mjs`: **115 scripts, no warnings, no errors.**
* `cd tools/mockup-2d && node --test`: **38 tests, all pass.** `cd bridge && node --test`: **45 tests, all pass.** (`npm test` in these two folders is `node --test`. I ran it directly, because `npm` uses the old Node here.) The mockup, the schema, the bridge and the adapters did not change.
* `node tools/export-scenes.mjs --check`: the files are what the mockup gives.
* Not run: `node tools/render-art.mjs --check` and `node tools/render-sound.mjs --check` (they need Chromium; the pictures and the sound files did not change, and the manifest check passes), and the benchmark and cost tools.

### Open questions (phase G-8)

1. **The sound switch in clips** (open question 4 of phase G-7). The clips show it, as the mockup's clips do. `--no-switch` hides it. Which should be the rule for the clips of the repository?
2. **A penguin that thinks in place can stand on a working penguin.** It has no spot, and it stays where it was, which may be a spot of a station that the next penguin has taken. It shows in `many`, `follow` and `ten`. Options: use the two spots `spotA` and `spotB` of `stations.gd` for it (it then walks a few steps; they have had no user since phase G-4), or let it walk to its rest point first. This changes the picture a little. Do you want it?
3. **The tour as a product** (open question 6 of the plan). It plays in the client and records. Should it ship, or stay a mockup aid?
4. **Clips from the container or from a GPU machine?** They are not equal to the last bit (see "The same frames on every run"). The plan says official clips come from the container.
5. **ffmpeg.** It is not on this machine. The recorder works without it and writes the command. Should the repository document a pinned ffmpeg, or only "ffmpeg with libx264 and AAC on the PATH"?


## Phase G-9: exports (Windows)

**Scope.** The owner postponed Linux and macOS ("do not build Linux and macOS binaries for now"). This phase is done for **Windows only**. The presets for Linux and macOS are in `export_presets.cfg` and a test checks them, but they are **not part of the result**. See "Linux and macOS: not built" below. The apps are **not signed**.

```bash
cd godot
export GODOT=/path/to/the/editor                 # the same editor as for the tests
node tools/export.mjs --templates-only           # the export templates: about 1.3 GB, one time
node tools/export.mjs --platform windows         # out/export/windows/AgentWorkshop.exe (one file)
node tools/startup.mjs --app out/export/windows/AgentWorkshop.exe --scene multi
node tools/cost.mjs --matrix --seconds 20 --app out/export/windows/AgentWorkshop.exe
```

The app takes the same options as the editor run, after `--`: `AgentWorkshop.exe -- --bridge=ws://127.0.0.1:8787/ws` or `-- --demo=multi`.

### What was added

| File | Content |
|---|---|
| `export_presets.cfg` | Three presets: `Windows Desktop`, `Linux`, `macOS`. No secret, no identity, no absolute path. `export_path` is empty: the tool gives it. |
| `tools/export.mjs` | Gets the templates, imports the project, and runs `--headless --export-release`. Options: `--platform windows\|linux\|macos\|all`, `--out`, `--debug`, `--templates-only`. |
| `tools/export.test.mjs` | The tests of the presets and of the tool (no export, no download). |
| `art/images/app_icon.png`, `.import` | The app icon, 512x512, made by the baker. In `MANIFEST.txt`. |
| `art/image_src/variants.js`, `bake.js`, `tools/render-art.mjs` (changed) | `APP_ICON` and its drawing. The 13 other image files are unchanged (checked: the baker gave the same bytes). |
| `project.godot` (changed) | `config/icon`, `config/version`, `import_etc2_astc=true` (the macOS export asks for it), `run/flush_stdout_on_print=true` (see decision 9). |
| `tools/cost.mjs`, `tools/startup.mjs` (changed) | The option `--app <path>` measures an exported app. |

### Decisions of phase G-9

The owner asked for these phases to run on their own. These are my choices. Each one can change.

1. **Templates.** `export.mjs` downloads `Godot_v4.7.2-stable_export_templates.tpz` (1.28 GB) from godotengine.org and checks its SHA-512 against the official `SHA512-SUMS.txt` (the hash is in the tool; the check passed). It unpacks only the files that the three platforms need (release and debug, x86_64, and `version.txt`, `icudt_godot.dat`) into the folder where the editor looks for them (`%APPDATA%/Godot/export_templates/4.7.2.stable/` on Windows). It then deletes the archive. The archive is one file, so the Linux and macOS files came with it. The download folder is `godot/.editor/` (git-ignored). The tool still unpacks all three platforms for `--platform all`. Use `--platform windows` to unpack only the Windows files (the tool does this now when the templates are missing).
2. **One file per app.** `binary_format/embed_pck=true`: the Windows app is one `.exe` with the data inside.
3. **`export_filter="all_resources"`.** The client builds the names of its sound files at run time, so a scan of the scenes would miss them. The exclude filter removes `test/*`, `tools/*`, `spikes/*`, `addons/*` (GUT), `out/*`, `art/image_src/*`, `art/sound_src/*`, `art/s6_support.gd`, `*.md` and `*.mjs`. The include filter adds `demo/*.json`. A test checks that nothing that `src/`, `demo/`, `art/images/` and `art/sound/` hold is excluded.
4. **Scripts as binary tokens** (`script_export_mode=1`). The compressed form (2) gave a start-up about 100 ms slower in one comparison of seven runs each. That is near the noise, so it is a weak choice.
5. **Name and version.** Product name `Agent Workshop`, version `0.1.0` (the version of the bridge package; `config/version` in the project and the presets agree, and a test checks it). The copyright line holds the copyright holder's name, as the license notices do. The company name is empty.
6. **The icon** is the head and the Krakow cap of the penguin on a rounded square, drawn by `penguin()` of `look.js`, made 16 times larger with no smoothing. It uses the colour of one hat cord as an accent. It has no Anthropic or Claude logo or mascot. Godot makes the other formats **from the PNG**: the Windows `.exe` got the icon and the version information with **no `rcedit`** (checked: the file properties show product name, version and copyright, and the icon shows on the file), and the macOS export wrote `icon.icns` (seen in the zip, not run). So no `.ico` or `.icns` file is kept in the repository. This answers the icon part of open question 4 of the plan.
7. **Unsigned.** `codesign/enable=false` for Windows. The tool and the presets have no signing, notarization or identity. The macOS preset uses the **built-in ad-hoc signature** (`codesign/codesign=1`; found by trying: 3 asked for the Xcode tools). An ad-hoc signature has no identity and no secret. An Apple-silicon Mac needs it to start the app at all. It does not remove the Gatekeeper warning. Not run on a Mac.
8. **The bundle identifier** of the macOS preset is `org.example.agentworkshop`. This is a placeholder. A real one needs a domain that the owner controls (open question 2).
9. **`run/flush_stdout_on_print=true`.** A release export does not flush `print`, so the log file that `cost.mjs` reads stayed empty while the app ran, and the tool could not see the window state. The setting makes `print` flush. The client prints only with `--log-events`, `--trace` and a few start-up lines, so the cost is small.
10. **The export prints its messages in the language of the editor** (not always English). The tool checks the exit code and the file, not the text.

### What a user sees (not signed)

* **Windows:** SmartScreen shows "Windows protected your PC" for an unsigned `.exe` that comes from the internet. The user must click "More info" and then "Run anyway". **Not seen here:** the file was built on this machine, so it has no "downloaded from the internet" mark. This text is from general knowledge, not from a run.
* **macOS (not a result):** Gatekeeper blocks an app that is downloaded and not signed and notarized. The user must open it with a right click ("Open") or allow it in the system settings. From the Godot documentation; not run.

### Windows: the proof for ADR 0008

Machine: Windows 11, Intel Core i7-11800H, NVIDIA RTX 3060 Laptop GPU, Godot 4.7.2 release template, OpenGL Compatibility. **A fast machine with a discrete GPU, not the reference laptop.**

**It holds on this machine.** I built `AgentWorkshop.exe`, started it on its own (no editor) and took screenshots of its window with a PowerShell script outside the repository. I looked at them.

1. **Live session.** A real bridge (`node src/cli.js serve`), the app started with `-- --bridge=ws://127.0.0.1:8787/ws`. The bridge logged "client connected (1)". The first screenshot shows the empty room. Then `replay ../schema/examples/claude-code-transcript.jsonl --speed 4`: the penguin walks to the map table, and the log lists Grep, Read and Edit with OK. Later screenshots show Task and WebSearch with OK, "Turn complete, 6 calls, 1 helper", the penguin on the stage, and confetti. The replay command printed "17 events" and "done". I did not check the order of all stations by screenshot (the replay test of G-8 does that with the editor build).
2. **Demo scenes from the menu.** `-- --demo=multi`: five agents, cards and the focus label. The key D opens the scene list. It shows eight lines: `live (bridge)` and the seven scenes (`arenas`, `follow`, `many`, `multi`, `session`, `ten`, `tour`). So the files of `demo/` are in the app and the list works. I started `tour` from the menu (the first card "THE ARENA, 2/31") and `ten` (four rooms in view, tabs, page boxes, the pointer).
3. **Not checked in the export:** the sound (nobody listened; the app starts with sound off), the scenes `arenas`, `many`, `follow` and `session` (I did not open them from the export), keys other than D, Up, Down and Enter, a run of hours.

### Size

| Export | Size | Note |
|---|---|---|
| Windows `.exe` (data inside) | **115.7 MiB** (121 MB) | The release template alone is 104 MiB (109 MB). The data are 11 MB. The plan said 30 to 70 MB: **that is wrong for the official templates.** |
| Linux (built once, not a result) | 81.7 MiB | |
| macOS zip (built once, not a result) | 66.5 MiB zip, 163 MiB unpacked | |

A smaller app needs a custom template build (without 3D, and so on). That is a larger task and was not tried.

### Cost of the release export (Windows, this machine)

`tools/startup.mjs --app` and `tools/cost.mjs --matrix --seconds 20 --app` (see "Phase G-6" for how they work). CPU is in percent of **one** core. **The "no focus" rows are forced** by `--force-focus=false` (the system kept the foreground window, as in G-6), except the `replay` row, which had a real loss of focus. The machine was in use during some runs, and the start-up numbers varied.

| Scenario | Focus (60 fps) | No focus (30 fps) | Minimized | Memory | Editor build of G-6 (focus / no focus / minimized / memory) |
|---|---|---|---|---|---|
| `idle`, 1 agent | 18.8 to 22.4 % | 10.0 to 13.9 % | 0.6 % (see below) | 205 to 208 MB | 20.1 / 10.0 / 0.9 / 229 MB |
| `replay`, 1 agent working | 22.6 % | 10.4 % | (see below) | 206 MB | 21.1 / 12.3 / 5.9 / 228 to 233 MB |
| `multi`, 6 agents | 25.7 % | 13.2 % | 1.3 % | 205 to 207 MB | 25.7 / 14.2 / 0.5 / 228 MB |
| `arenas`, 9 agents | 25.9 % | 14.0 % | (see below) | 206 MB | 29.0 / 15.2 / 0.5 / 228 MB |
| `ten`, 157 agents | 55.4 % | 31.8 % | 0.7 % | 219 MB | 79.6 / 45.1 / 1.0 / 250 MB |

* **Minimized:** in the matrix run the window came back (the system, or a person, restored it) and the `idle`, `replay` and `arenas` rows read 6.9, 6.0 and 3.7 %. Two repeats of `idle` stopped with "the window left the state" (the tool checks the state at the end), and one clean `idle` run gave 0.6 %. So I count the minimized cost as about 0.6 to 1.3 %, and I do not trust the three high rows.
* **Memory** is 20 to 30 MB lower than in the editor build, about 205 MB with one agent. An empty project in a release export was **not** measured, so the floor of the engine is not known.
* **CPU** is the same as in the editor build for few agents, and about 30 % lower for `ten`. The release export does **not** change the finding of G-6: the engine alone costs more than the plan's budgets.
* **Start-up** (warm, seven runs, medians): `multi` 1.9 to 2.1 s in three sets (editor build: 2.24 s), `ten` 2.3 s in one set and 4.5 s in a later set when the machine was busy (editor build: 2.56 s). Of that, the time from the start of the engine to the `_ready` of the view is 1.7 to 1.9 s. **Cold start:** the first run of each set is left out, so every number is warm (files in the cache of the system and of the driver). The first start after a restart was not measured.

### Proposed budgets (proposals, not decisions)

The reference laptop (a low-end laptop with 8 GB) was **not measured**. These numbers come from the release export on the fast machine above. A low-end laptop will need more CPU time, so the owner should measure it before these numbers become budgets. **Do not read them as "the reference laptop is met".**

| What | Plan (a guess) | Proposed | Measured here (release export) |
|---|---|---|---|
| Time to the first frame of the room (warm) | 2 s | 3 s | 1.9 to 2.1 s (`multi`) |
| CPU, no focus, 1 agent working | 2 % | 15 % | 10 to 14 % |
| CPU, no focus, 12 agents working | 5 % | 20 % | 13 to 14 % (6 and 9 agents; 12 were not run) |
| CPU, with focus, 1 to 9 agents (60 fps cap) | not set | 30 % | 19 to 26 % |
| CPU, minimized | 0.5 % | 1.5 % | 0.6 to 1.3 % |
| Memory, `multi` | 200 MB | 250 MB | 205 to 207 MB |
| Size of the app | 30 to 70 MB | 130 MB (official template) | 115.7 MiB |

Why: an empty Godot project in the editor build costs 6.4 % at 30 fps and 193 MB (G-6), so 2 % and 5 % cannot be met by this engine in this setup. A lower frame rate without focus (15 fps) or "draw only when the picture changes" would cut the CPU, and it changes the look a little. That is a decision for the owner (open question 1).

### Linux and macOS: not built

* The owner postponed both. Their presets are in `export_presets.cfg` and `export.test.mjs` checks them (names, no secret, filters, the ad-hoc signature, no absolute path). The tool can build them (`--platform linux|macos`).
* **What I did before the owner's order arrived**, so you know what exists: my first command used `--platform all`, so I built both once. The Linux binary ran in the container of G-8 (Xvfb, Mesa software renderer) against a real bridge, and a screenshot showed the room and a penguin with log lines (Read, Edit, Bash with OK) from the replay. The macOS zip was built (it holds `AgentWorkshop.app`, `icon.icns` and an ad-hoc signature) and **not run**: there is no Mac here. I do not count either as a result of this phase: Linux was one run in one container, and macOS was never started. I did not repeat or extend them. The files are in the git-ignored `out/export/`.
* **Not verified at all:** macOS on real hardware (the executable flag, Gatekeeper, the ad-hoc signature on Apple silicon), Linux on a real host, and the icon in the macOS bundle.

### What was checked, and what was not

* **Checked:** `node tools/run-gut.mjs` (48 scripts, 609 tests, all pass), `node --test` in `godot/` (185 tests, all pass, none skipped; it renders the pictures again with Chrome), `node tools/check.mjs` (115 scripts, no warnings), `cd tools/mockup-2d && node --test` (38 pass) and `cd bridge && node --test` (45 pass). `node tools/render-art.mjs --check` passed before the icon was added; the full render after it gave the same bytes for the other 13 files.
* **Not run:** a full export inside `node --test` (by design), signing, notarization, an installer, a run on the reference laptop, a cold start, Linux or macOS as a result, the sound in the export.

### Open questions (phase G-9)

1. **The budgets.** Take the proposed numbers, or decide to cut the cost (a lower frame rate without focus, or draw only when the picture changes)? Name the reference laptop and measure the release export on it.
2. **The macOS bundle identifier.** `org.example.agentworkshop` is a placeholder. Which reverse-domain name will the project own?
3. **The size.** The official template makes a 115 MiB Windows app. Is that acceptable for a download, or should a custom template build be tried? (The plan said 30 to 70 MB.)
4. **A start-up of about 2 s with 1.7 s in the engine.** The export did not make it much smaller. Show an early first frame (a small scene) while the rest loads?
5. **Signing and publishing** (plan open question 11): unchanged, nothing is signed.
6. **When to build Linux and macOS.** The owner postponed them. The tool and the presets are ready.



## Open points

* `node --test` needs Node 20 or later. On Node 16 the tests do not start.
* The hashes in `tools/get-godot.mjs` come from the file `SHA512-SUMS.txt` of the release `4.7.2-stable` in
  `godotengine/godot-builds`. The download itself (from `downloads.godotengine.org`) was **not run**, because the
  owner's editor was set in `GODOT`. Only its address and the hash code were tested.
