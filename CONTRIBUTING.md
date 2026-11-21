# Contributing

## Set up

With [mise](https://mise.jdx.dev) (it pins Node 24 and Rust, and lists the tasks in `mise.toml`):

```bash
mise install          # once
mise tasks            # all tasks
```

| Task | What it does |
|---|---|
| `mise run bridge` | Run the bridge from the source |
| `mise run replay` | Send the example Claude Code session to the bridge |
| `mise run app` | Run the app. Start the bridge first. Extra arguments go after `--`, for example `mise run app -- --start-bridge=bridge/target/release/agent-workshop-bridge` |
| `mise run demo` | The app on a made-up scene, no bridge (`mise run demo arenas` for another scene) |
| `mise run check` | Everything the CI checks: version, fmt, clippy, bridge tests, adapter tests, Godot tests (downloads the Godot editor the first time) |
| `mise run check-fast` | The same without the Godot tests |
| `mise run deny` | `cargo deny` (advisories, licenses, sources) and the check of the bridge's third-party notices |
| `mise run notices` | Write `bridge/THIRD-PARTY-NOTICES.txt` again. Run it when `Cargo.lock` changes (a Dependabot update of the bridge needs it) |

`mise run check` covers the system you run it on. A failure that only Windows or Linux has shows in the CI.

Without mise you need Rust (stable), Node 20 or later, and the Godot editor in the version in `godot/GODOT_VERSION`. Set `GODOT` to the editor, or run `node godot/tools/get-godot.mjs` to download it into `godot/.editor/`. On Windows use the console build of the editor, because it prints to the terminal. Details are in [godot/README.md](godot/README.md).

## Run from the source, without mise

```bash
cd bridge && cargo run --release -- serve                                         # the bridge
cd godot && "$GODOT" --headless --path . --import                                 # once: import the project
cd godot && "$GODOT" --path .                                                     # the app
cd bridge && cargo run --release -- replay ../schema/examples/claude-code-transcript.jsonl --speed 4   # events
cd godot && "$GODOT" --path . -- --demo=multi                                     # a made-up scene, no bridge
```

The app takes its options after `--` (listed in [godot/README.md](godot/README.md#run)).

## Tests

```bash
cd bridge && cargo test                        # the bridge: unit tests, and tests with the real binary, real HTTP and real WebSocket clients
node --test 'adapters/test/*.test.mjs'         # the OpenCode plugin, Pi extension and Hermes script against the real bridge (Node 22 or later)
cd godot && node tools/run-gut.mjs             # GUT tests, headless
cd godot && node --test                        # Node tests: bridge link, license split, tools
cd godot && node tools/check.mjs               # GDScript check: warnings count as errors
```

The `godot/` commands need `GODOT`. The tests that start the bridge build it with `cargo build` first. Set `ARENA_BRIDGE_BIN` to use a binary you already have.

`bridge/tests/` also checks `godot/test/fixtures/`. When `schema/examples/` or the adapters change, make the fixtures again with `cd bridge && cargo run --example fixtures`.

## Third-party notices

The archives of the bridge and of the app carry `THIRD-PARTY-NOTICES.txt`, as the licenses of the parts they contain ask. `bridge/THIRD-PARTY-NOTICES.txt` is made from `Cargo.lock` by `mise run notices`, and CI fails when it is out of date. `godot/THIRD-PARTY-NOTICES.txt` is made by the Godot engine itself, for the pinned version. Make it again when `GODOT_VERSION` changes:

```bash
cd godot && "$GODOT" --headless --path . -s res://tools/licenses.gd -- --out=THIRD-PARTY-NOTICES.txt
```

## Record a scene

You need a window and `ffmpeg`:

```bash
cd godot && node tools/record.mjs --scene arenas                           # out/arenas.mp4, 1920x1080
cd godot && node tools/record.mjs --scene multi --stills 19.5 --no-switch  # a still, as in docs/images/
```

## Build the apps and release

```bash
cd godot && node tools/export.mjs --platform windows     # out/export/windows/AgentWorkshop.exe
# also: windows-arm64, linux, linux-arm64, macos (universal), all
```

The first export downloads the export templates (about 1.3 GB). How a release is made is in [docs/releasing.md](docs/releasing.md).

## Rules

1. Write documents and comments in simple technical English.
2. The event schema (`schema/event.schema.json`) is the contract. Adapters map native events to it. The app reads only the schema and picks stations by `category`, never by tool name. Keep `bridge/src/schema.rs` in step with it (a test checks the enums).
3. The bridge listens on `127.0.0.1` only, stores nothing and broadcasts only schema fields.
4. The app has a look of its own. Do not use Anthropic or Claude logos, the Claude Code mascot, Anthropic's typefaces, Claude's colours as a colour scheme, the asterisk spinner and its verbs, or layouts copied from Claude Code's terminal.
5. This repository is public. Do not add personal data, real transcripts, real paths or names, or references to private projects. Example sessions are made up.
6. "Agent Workshop" is the project. An "arena" is one room of the app. Existing code names (`ARENA_*` variables, `arena.js`) stay as they are.
7. Code is MIT. Art is all rights reserved ([LICENSE-ASSETS](LICENSE-ASSETS)). Drawing and sound code (the palette, sprites, props, room, effects, interface drawing, music and event sounds) lives only in `art/` folders (`godot/art/`), and each file there starts with the copyright header. Images and sounds made from the art code are art too: in `godot/art/` they live in `images/` and `sound/`, and `MANIFEST.txt` holds their hashes. Code outside `art/` may call the art but must not contain it. `cd godot && node --test` checks the headers and the split.
