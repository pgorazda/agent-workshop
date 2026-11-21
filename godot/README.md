# Agent Workshop: the Godot app

This folder holds the app: a 2D client made with Godot that reads the event stream of the bridge and draws the workshop. The README in the repository root says how to run it. [CONTRIBUTING.md](../CONTRIBUTING.md) says how to work on it. This file lists the folders, the options, and the tests.

## Folders

| Path | Content |
|---|---|
| `GODOT_VERSION` | The pinned Godot version (standard build, not .NET) |
| `project.godot` | 2D only, Compatibility renderer, 480x270 viewport, integer scaling, nearest filtering |
| `src/core/` | Classes with no nodes and no drawing: the event, the options, the arena rules and camera, the director, the penguin actors, the focus, the log and bar models, the sound model |
| `src/net/` | The WebSocket link to the bridge, the demo timeline player, and the launcher that starts the bridge |
| `src/view/` | The live view, the camera view, and what turns an actor into drawing |
| `src/main.tscn`, `src/live.tscn` | The text view of the events, and the live view (the main scene) |
| `demo/` | The seven made-up scenes (JSON timelines) |
| `art/` | The art, not MIT (see `LICENSE-ASSETS`): drawing code, the generated atlas data, the PNG and WAV files in `images/` and `sound/`, their source in `image_src/` and `sound_src/`, and `MANIFEST.txt` (hashes) |
| `addons/gut/` | GUT 9.7.1 (MIT), the test framework, kept in the repository |
| `test/` | GUT tests. `test/fixtures/` holds the example sessions as canonical events and the golden data of the arena rules |
| `tools/` | Node scripts and their tests: export, recording, rendering of art and sound, the bridge link test, the license check |

## Set up

You need three things.

1. **Node 20 or later.** The scripts in `tools/` use it.
2. **Rust**, for the bridge (a stable toolchain, <https://rustup.rs>). The tests that start the bridge build it with `cargo build` first. You can instead set `ARENA_BRIDGE_BIN` to a bridge binary, for example one from a release.
3. **The Godot editor, in the pinned version.** Use one of these ways:
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
cd bridge && cargo run --release -- serve    # the bridge, on 127.0.0.1:8787 (or a downloaded one: agent-workshop-bridge serve)
cd godot && "$GODOT" --path .          # the app (import the project once: "$GODOT" --headless --path . --import)
cd bridge && cargo run --release -- replay ../schema/examples/claude-code-transcript.jsonl --speed 4   # events for the app
```

The app shows one room. Each agent that sends an event gets a penguin, and the penguin walks through the stations. The bridge keeps no
history, so start the app first and then the replay. To play a scene with no bridge:

```bash
cd godot && "$GODOT" --path . -- --demo=session     # or --demo=multi
```

Keys: F switches between AUTO and MANUAL, Tab opens and closes the
overview, Esc leaves it, Left and Right go to another arena (another page in the overview), N goes to the arena that needs you. Sound: M turns all sound on or off, S opens the sound menu (1 to 4 pick a tune, 0 none, E the event sounds, Esc closes it). In demo mode
Space pauses, 1 to 3 set the speed (1x, 2x, 4x) while the follow menu and the sound menu are closed, and `[` and `]` change it (0.5, 1, 2, 4). R starts the scene again, D opens the list of scenes
(Up, Down, Enter, Esc), C hides the bar. A scene starts again two and a half seconds after its end. A click on a tab, a page box, an arena in the
overview, a penguin or a card does what it says; the follow switch opens its menu.

Command-line options come after `--`:

| Option | Meaning |
|---|---|
| `--bridge=ws://127.0.0.1:8787/ws` | The bridge address. This value is the default. |
| `--start-bridge[=<path>]`, `--no-start-bridge` | Start the bridge program when no bridge answers at the address (off by default). `<path>` names the program. See "Start the bridge from the app". |
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
| `--benchmark=<scene>`, `--benchmark-out=<file>`, `--vsync=on\|off` | Play a scene in real time and write a CSV of the frames. |
| `--unfocused-fps=<n>`, `--focused-fps=<n>` | The frame rate of a window with no focus (30 by default) and with focus (60 by default). 0 is no cap. |
| `--frame-stats` | Print the average cost of the parts of a frame every 5 s. |
| `--startup-report=<file>` | Write the times of the start-up to a file after the first frames, and quit. |
| `--reduced-motion` | The room does not shake after a failure. |
| `--sound=<tune>\|on\|events\|off` | Start with sound on: a tune (krakowiak, kujawiak, oberek, goralski), `on` (the default tune and the event sounds), `events` (event sounds only). All sound is off without it. |
| `--record-fps=<n>`, `--record` | Recording mode at `n` frames a second (30 for `--record`). Started by `tools/record.mjs` together with the engine's `--write-movie` and `--fixed-fps`. |
| `--stills=<s,...>`, `--stills-out=<folder>` | Recording mode: run with no drawing up to each time, draw one frame, and save it as `still-<n>.png`. |
| `--menu=<s>`, `--events=0`, `--no-switch` | Recording: the sound menu is open for the first seconds, no event sounds (the tune plays), and no sound switch. |
| `--trace` | Print `[trace] <who>: <station>` when a penguin begins to visit a station. |

Example: `"$GODOT" --headless --path . -- --bridge=ws://127.0.0.1:9000/ws --log-events`.

### Start the bridge from the app

The app can start the bridge for you. It is off by default, and there are two ways to turn it on:

* `--start-bridge` or `--start-bridge=/path/to/agent-workshop-bridge` on the command line (`--no-start-bridge` turns it off, and wins over the file);
* the file `user://settings.cfg`, which is in the user data folder of the app (the Godot "user://" folder of the project `Agent Workshop`):

  ```ini
  [bridge]
  start=true
  path="/path/to/agent-workshop-bridge"   ; optional
  ```

There is no switch in the interface, by decision. The rules (`src/net/bridge_launcher.gd`):

* It starts a bridge only for a local address (`ws://127.0.0.1`, `ws://localhost` or `ws://[::1]`), with `--host 127.0.0.1` and the port of the address. For any other address it does nothing and shows a note.
* It first asks `GET /health` at the address (500 ms). If a bridge answers, the app uses it and never stops it.
* The program is the configured path, or `agent-workshop-bridge` (`.exe` on Windows) next to the app (on macOS also next to the `.app`), or on the `PATH`. The app never downloads it.
* One try for each run of the app. If it fails (no program, the port is taken, the program ends at once), one short note shows in the status line, and the client keeps trying to connect.
* When the app quits, it stops the bridge that it started. If the app crashes or is killed, the bridge ends too: the app holds a pipe to the standard input of the program, and the program is started with `--exit-when-stdin-closes`.
* It reads the output of the program all the time in two threads, so a bridge that logs a lot cannot block on a full pipe.

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
| `node --test` | All Node tests in `tools/`: the bridge link, the license check, the scene files, the download script. They start the real bridge. |
| `node tools/check.mjs` | Loads every GDScript file in a debug run and fails on any warning or error. |
| `cargo run --example fixtures` (in `bridge/`) | Makes `test/fixtures/*.events.jsonl` again. Run it when `schema/examples/` or the bridge adapters change. `cargo test` in `bridge/` fails when the fixtures are out of date. |
| `node tools/render-art.mjs` | Renders the pictures with the art code in `art/image_src/` in headless Chromium. Needs Playwright, `CHROMIUM_PATH` and the two fonts (`npm install --no-save @fontsource/tiny5@5.3.0 @fontsource/silkscreen@5.3.0` here). Add `--check` to render twice and compare with the files on disk. |
| `"$GODOT" --path . -s res://tools/shot.gd -- --scene=res://src/room.tscn --out=room.png` | Saves the 480x270 viewport of a scene as a PNG file after a few frames. It needs a window (not `--headless`). `--count=5 --frames=600` with `%d` in `--out` saves several pictures. |
| `node tools/record.mjs --scene tour` | Records a scene as a 1920x1080 clip (needs a window and ffmpeg). `--stills 7,22.5` saves stills. `node tools/determinism.mjs` records a scene twice and compares every frame. |
| `node tools/startup.mjs`, `node tools/cost.mjs` | The time to the first frame, and the CPU and memory in each state of the window. They need a window. `cost.mjs` takes `--engine-arg=` (for example `--engine-arg=--audio-driver --engine-arg=Dummy`) and `--client-arg=--sound=krakowiak`. |
| `node tools/sound-levels.mjs` | The levels of each tune with each event sound, from the files in `art/sound/`, and how far the sum goes above full scale. |
| `"$GODOT" --path . -s res://tools/ui_shots.gd -- --out=<folder> --shots="arenas:12:menu,..."` | Stills of the live view in chosen states (a menu, a hover, the overview) in one run. |
| `node tools/benchmark-report.mjs run.csv` | Prints the frame times of the long camera moves of a benchmark run (`"$GODOT" --path . -- --benchmark=ten --benchmark-out=run.csv`, which needs a window). |

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
