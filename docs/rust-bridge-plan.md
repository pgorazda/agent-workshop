# Plan: the bridge in Rust

**State: a plan. Nothing is built. The decision is ADR 0013 (proposed). Phase R-0 settles it. The owner answered the first open questions on 2026-11-21 (see "Decided by the owner").**

## Goal

Replace the Node bridge in `bridge/` with a Rust program. It builds to one binary per platform. A person who wants live events downloads the binary and runs it. They do not install Node or run `npm ci`.

Today the release has only the Godot apps. The bridge is not in it, so live use needs Node 20 and `npm ci`. This plan closes that gap.

The port is ready when:

* the binary gives the same output as the Node bridge for the same input (see "Parity");
* every ported test passes on Linux, macOS and Windows;
* the Godot link tests pass against the binary;
* the release has a separate bridge archive for each of the five platforms of the apps;
* a person with no Node follows the README and sees a penguin.

Not in scope of phases R-0 to R-7: changes to the event schema, to the HTTP and WebSocket contract, to the adapters' mapping rules, or to the scripts in the adapters' folders (`adapters/`, which use `curl`, a plugin or an extension). No new framework. No Paseo source (ADR 0009 needs no change: its sidecar posts to the same `POST /event`). The Godot app starting the bridge is phase R-8, after the cutover, and has its own ADR.

Node stays for contributors. The scripts in `godot/tools/` and the release scripts are `.mjs` files. Only people who run the bridge stop needing Node.

## Decided by the owner on 2026-11-21

1. **The bridge has its own archives.** It is not put inside the app archives. A person downloads the app, and the bridge if they want live events.
2. **macOS gets one universal binary** (Intel and Apple silicon), like the app.
3. **The Godot app gets a setting that starts the bridge by itself.** This is phase R-8. It comes after the cutover and has its own ADR first.
4. **Parity first.** The OpenCode adapter's id sets that never shrink are kept as they are in the port. A fix is a separate change after R-7.

## What exists

| Piece | Lines | Notes |
|---|---|---|
| `bridge/src/server.js` | 140 | `POST /event`, `POST /hook/<framework>`, `GET /health`, `WS /ws`. 10 MB body limit. `hello` message to each new client |
| `bridge/src/cli.js` | 117 | `serve`, `replay`, `ingest pi`. Flags and the `ARENA_*` environment variables |
| `bridge/src/schema.js` | 98 | `normalizeEvent`, `validateEvent`. The error texts are part of the HTTP 400 answer |
| `bridge/src/categories.js`, `targets.js` | 114 | Tool name to category. Target text from a tool input |
| `bridge/src/adapters/` | 611 | Claude Code (hook and transcript), OpenCode, Pi, Hermes. OpenCode, Hermes and Claude Code keep state per session |
| `bridge/test/` | 876 | 8 files, 45 tests. The server tests use a real server and a real WebSocket client |
| Users of the bridge in `godot/tools/` | | `example-events.mjs` imports the adapters. `bridge-link.test.mjs` and `replay.test.mjs` import `createBridge`. `cost.mjs` starts `cli.js`. `version.mjs` edits `bridge/package.json` and its lock file |

The only dependency is `ws`. It has no dependencies of its own.

## Decisions for the design

1. **One crate, a library and a binary.** `src/lib.rs` holds the modules (`schema`, `categories`, `targets`, `adapters/*`, `server`). `src/main.rs` is the CLI. Tests call the library.
2. **Develop in `bridge-rs/`, move it to `bridge/` at the cutover.** The Node bridge stays beside it as the reference until phase R-7. Both are tested in CI until then.
3. **The binary is named `agent-workshop-bridge`.** The commands and flags stay as they are: `serve`, `replay`, `ingest pi`, `--port`, `--host`, `--redact-targets`, `--speed`, `--max-gap`, `--url`, `--tee`. The variables `ARENA_HOST`, `ARENA_PORT`, `ARENA_REDACT_TARGETS` and `ARENA_BRIDGE_HTTP` stay (rule 6 of `CLAUDE.md`).
4. **Events are `serde_json::Value`, not typed structs.** The adapters read payloads where every field is optional and may have the wrong type. `POST /event` keeps unknown extra fields (the schema says so). A `Value` keeps both behaviours. The adapters build events with a small builder that leaves out fields that are not set (the same as `undefined` in JavaScript).
5. **Shared state sits behind one `Mutex`.** The adapters keep per-session maps and sets. A request takes the lock, maps the payload to events, releases the lock, and then broadcasts. No `await` while the lock is held.
6. **Libraries.** Default: `tokio`, `axum` (with `ws`), `serde_json`, `clap`, `ureq` (blocking, no TLS, for `replay` and `ingest`) and one time library for RFC 3339 dates. Alternative: `tiny_http` and `tungstenite` with threads, which has a much smaller crate tree. Phase R-0 picks one by crate count and binary size. The bridge has a few clients, so both would work.
7. **A slow client does not block the others.** Each client has a bounded queue (4096 events). When it overflows, events are dropped for that client and a line is logged. The bridge keeps no history, so a dropped event cannot be sent later.
8. **Bind to `127.0.0.1` by default. No Origin check.** The Godot client sends no `Origin` header, and the Node bridge accepts that. The test `bridge-link.test.mjs` keeps checking it.
9. **A stripped release build.** `opt-level = "s"`, `lto = true`, `codegen-units = 1`, `panic = "abort"`, `strip = true`. Linux builds use musl, so the binary is static.

## Parity

The Node bridge is the specification until the cutover. "Same" means: the same JSON after parsing (not the same key order), the same status codes, the same error texts.

Known differences, accepted on purpose. Each one gets a test that shows it:

| Case | Node | Rust |
|---|---|---|
| Long `target` or `error` text | cut by UTF-16 units (it can split a surrogate pair) | cut by characters |
| Very deep JSON (more than 128 levels) | parsed | `400` (the `serde_json` limit) |
| Integers above 2^53 | rounded | kept as sent |
| Time strings in transcripts | `Date.parse`, which accepts many formats | RFC 3339 only. Other formats count as "no time", as a failed `Date.parse` does today |

Every other difference found in phase R-5 is a bug in the Rust code, or it is added to this table with a reason.

Places where JavaScript's loose typing shows, and which the port must copy for the cases that real payloads reach: `String(x)` on a value that is not a string (used in `describeTarget` and for the permission text), `??` on `null` and missing fields, `Boolean(response.error)`, a number in `session_id` (the event is then rejected by `validateEvent`, as today), and `arr[0]` on an empty array.

## Phases

Each phase ends with a pull request that passes CI. The effort numbers are a rough guess, in working days.

### R-0: spike and decision (0.5 day)

* Make the crate with `GET /health`, `WS /ws` with `hello`, and a broadcast of events posted to `POST /event`.
* Build the two library stacks from decision 6. Record the crate count, the stripped size and the idle memory of each. Record the idle memory of the Node bridge on the same machine.
* Check that CI can build on all five targets: `ubuntu-24.04` and `ubuntu-24.04-arm` (musl), `windows-2025` and `windows-11-arm` (MSVC), `macos-latest` (both Apple targets, then `lipo`). These runner names and their availability for this repository need checking. The fallback is cross-compiling from Linux (`cargo-zigbuild` for Linux and macOS, `cargo-xwin` for Windows).
* Run the existing Godot client against the spike (`bridge-link.test.mjs` style, by hand). It must connect with no `Origin` header.
* Accept or reject ADR 0013. If the numbers are poor, stop here and use the single-file JavaScript binary instead (see the ADR).

### R-1: core (0.5 day)

`schema.rs` (constants, `normalize_event`, `validate_event` with the same error texts), `categories.rs`, `targets.rs`. Port `schema.test.js`. Add a test that reads `schema/event.schema.json` with `include_str!` and compares its enums with the constants (the check that `schema.js` has today).

### R-2: adapters (2 days)

In this order, each with its tests: Pi (110 lines, no state), Hermes, Claude Code (hook, then transcript), OpenCode (the most state: six maps and sets). Port `claude-code.test.js`, `hermes.test.js`, `opencode.test.js` and `pi.test.js`.

`pi-extension.test.js` is different: it imports the TypeScript extension in `adapters/pi/` (Node strips the types) and checks that the events it sends are mapped by the adapter. Rust cannot import that file. Split the test in two. A Node test runs the extension with fake input, captures what it sends, and compares it with a fixture file. It needs no npm package, so it moves to `adapters/pi/`. A Rust test maps the same fixture and checks the events.

Add a made-up hook corpus, `schema/examples/claude-code-hooks.jsonl`. The examples folder has the raw Claude Code transcript but no raw Claude Code hook payloads, so the live `fromHook` path has no example today. The new file is written by hand and holds no real data (rule 5).

### R-3: server (1 day)

`server.rs`: the routes, the status codes and the answers of `server.js`, the 10 MB limit with `413` and `{"error":"payload too large"}`, `404 {"error":"not found"}`, the `hello` message, `--redact-targets`, the log lines, clean shutdown. Port `server.test.js` (a real server on a free port, a real WebSocket client).

### R-4: CLI (0.5 day)

`main.rs`: `serve`, `replay`, `ingest pi`, the environment variables, the usage text, exit codes. `ingest pi` must fail open: a missing bridge never breaks the agent's output, and each post has a 1 second timeout. Test `replay` and `ingest` against the Rust server, with `--speed 0`.

### R-5: parity and the Godot tests (1.5 days)

* **Golden check.** The Rust tests convert every file in `schema/examples/` and compare with `godot/test/fixtures/*.events.jsonl` (made today by the Node adapters).
* **Differential check.** A script (`bridge-rs/tools/diff.mjs`) starts both bridges, posts the same payloads to both, and compares what a WebSocket client receives. Inputs: the corpora in `schema/examples/`, then the same payloads with a mutation each (a field dropped, a field set to `null`, a number, an empty string, an empty array, a very long string, a character outside the basic plane). Every difference is a Rust fix or a row in the table above. The script runs in CI until the cutover.
* **Godot tests.** Change `bridge-link.test.mjs`, `replay.test.mjs` and `cost.mjs` to start the binary (a built path from an environment variable, or `cargo build` first) instead of `createBridge` and `cli.js`. The restart test kills the process and starts it again on the same port. `example-events.mjs` and its test are replaced by `bridge-rs/examples/fixtures.rs`, which writes the fixtures (`cargo run --example fixtures`). A `cargo test` fails when `godot/test/fixtures/*.events.jsonl` are out of date. The Godot tests only read the fixtures.

### R-6: CI and release (1.5 days)

* `ci.yml`: a Rust job on three systems (Linux, macOS, Windows): `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`, and `cargo deny check` (licenses and advisories). The Node bridge job stays until R-7. Dependabot gets a `cargo` entry.
* `release.yml`: a matrix job builds the binary for the five platforms on native runners, runs `agent-workshop-bridge --help` and a short `serve` and `/health` check on each, and uploads the files. The macOS job builds both Apple targets and joins them with `lipo`. The release job downloads these files and the app archives.
* `package.mjs`: also makes the bridge archives. The names are `AgentWorkshopBridge-<version>-<os>-<arch>` with `.zip` (Windows and macOS) or `.tar.gz` (Linux), and `macos-universal` for macOS. Each archive holds one folder with the binary and `LICENSE` (the bridge is code, so no `LICENSE-ASSETS`). The Linux binary and the macOS binary keep the executable flag. `SHA256SUMS` lists the bridge archives too, and the attestation covers them. Update `package.test.mjs`.
* `docs/releasing.md`: add the bridge archives to the table of files.
* `version.mjs`: the version places change from `bridge/package.json` and `bridge/package-lock.json` to `bridge/Cargo.toml` and the `agent-workshop-bridge` entry of `Cargo.lock`. Update `version.test.mjs`.
* macOS: the binary is not signed or notarized, as the apps are not. A downloaded unsigned binary gets the quarantine flag, and Gatekeeper blocks it. Apple silicon needs at least an ad-hoc signature, so run `codesign --force --sign -` after `lipo`. The release notes tell the user how to open it. Windows shows SmartScreen. Both match what `docs/releasing.md` says about the apps.
* Make the first release after this a pre-release.

### R-7: cutover (0.5 day)

Do this after one pre-release was run on at least two platforms by hand.

* Delete `bridge/src/`, `bridge/test/`, `package.json` and `package-lock.json`. Move `bridge-rs/` to `bridge/`. Remove the Node bridge job and the differential script.
* Update every place that names the Node bridge: `README.md` and `README.pl.md` (the Polish translation is changed in the same step), `godot/README.md` (it names `example-events.mjs`, and tells the reader to run `npm ci` in `bridge/`), `docs/releasing.md`, the Pi `ingest` lines in `adapters/` and the root README, the test commands and rule 2 in `CLAUDE.md` (`bridge/src/schema.js` becomes `bridge/src/schema.rs`), and the `.github/dependabot.yml` npm entry. The plans in `docs/` that say "bridge (Node)" get a short note.
* Quick start becomes: download the bridge archive for your system, run `agent-workshop-bridge serve`, start the app. Building from source needs Rust (`cargo run -- serve`).

### R-8: the app starts the bridge (after R-7)

The owner wants a setting in the Godot app that starts the bridge by itself. Write the ADR first (the next free number). It must answer the questions below, and it touches rule 3 (the bridge stays on `127.0.0.1`, stores nothing and broadcasts only schema fields).

* **Where the app finds the bridge.** The archives are separate, so the app cannot count on a file next to it. Options: look for `agent-workshop-bridge` next to the app and on the `PATH`, and let the person pick a file in the setting.
* **Default.** Off, so the app never starts a program that the person did not choose.
* **When it starts.** Only when `GET /health` on the configured address gets no answer. If a bridge already runs, the app uses it.
* **Who stops it.** The app stops a bridge that it started, when it quits (also after a crash of the app, so no bridge is left behind). It never stops one that it did not start.
* **Port clash.** Another program holds the port: show a short message and use the demo mode.
* **Errors.** Show the first lines of the bridge's output when it exits at once.
* **Code.** The process handling sits outside `art/` (rule 7). Test it with a fake bridge program, and with the real binary in the Godot link test.

## Risks

| Risk | What to do |
|---|---|
| The Rust adapters drift from the Node ones in odd cases | `Value`-based code, the golden and differential checks, the table of accepted differences |
| More dependencies than today (`ws` has none; an `axum` tree has dozens) | `Cargo.lock` is committed, `cargo deny` runs in CI, Dependabot watches it, and R-0 compares it with the small `tiny_http` stack |
| A runner for Windows on ARM or Linux on ARM is not available | Cross-compile (see R-0). Worst case, ship those two later |
| The first Godot client run against the Rust bridge fails on the handshake | R-0 checks it first, and `bridge-link.test.mjs` keeps checking it |
| A deep payload gets `400` and an event is lost | Accepted (see the table). The hook scripts already ignore the answer. Revisit if a real payload reaches the limit |
| The port takes longer than the single-file JavaScript binary would have | R-0 gives the numbers first. Stop there if they are poor |

## Open questions

None for R-0 to R-7. The questions for R-8 are in its section. After R-7, one change is left for later: the OpenCode adapter's id sets never shrink (decision 4 above).
