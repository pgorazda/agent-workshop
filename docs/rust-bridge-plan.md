# Plan: the bridge in Rust

**State (2026-11-21): phases R-0 to R-8 are built and checked on one machine (macOS, Apple silicon), (the owner decided that R-8 needs no switch in the interface). Not yet run: the CI and release workflows, and the builds for Linux and Windows (see "What was checked"). The decision is ADR 0013 (accepted on 2026-11-21, with ADR 0014 and the differences below).**

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
4. **Parity first.** The adapters keep their state as the Node code did. A fix is a separate change after R-7. (The first plan said that the OpenCode id sets never shrink. That was wrong: they are cleared when they hold 5,000 ids. The maps of sessions of the OpenCode and Hermes adapters do grow, until a session is deleted or forever.)

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

Known differences, accepted on purpose. Each one has a test that shows it (`bridge/tests/server.rs`, the unit tests of `schema.rs` and `claude_code.rs`):

| Case | Node | Rust |
|---|---|---|
| Long `target` or `error` text | cut by UTF-16 units (it can split a surrogate pair) | cut by characters |
| Very deep JSON (more than 128 levels) | parsed | `400` (the `serde_json` limit) |
| Integers above 2^53 | rounded | kept as sent |
| Time strings in transcripts | `Date.parse`, which accepts many formats, and a number is turned into a text first (the number 0 is the year 2000) | RFC 3339 texts only. Anything else counts as "no time", as a failed `Date.parse` does. Claude Code writes RFC 3339 |
| The text of a JSON syntax error in a `400` answer | the words of the JavaScript parser | the words of `serde_json`. The status and the `error` field are the same |
| `POST /hook/constructor` | `500` (a quirk of JavaScript objects: `constructor` is a property of every object) | `404` like any unknown framework |
| A lone surrogate escape in JSON (`"\ud83d"`, from a text cut in the middle of an emoji) | read, the text keeps the lone half | read, the escape becomes U+FFFD (a Rust string cannot hold a lone half). The event is not lost |
| Numbers outside the range of a double (`1e999`) | read as `Infinity`; the event is then rejected as "ts must be a number" or ignored | `400 number out of range` (the whole post is rejected) |
| `String(number)` of very small or odd numbers in `target` or `error` | JavaScript's text (`1e-7`) | whole numbers, `-0` and numbers from 1e21 match; very small numbers keep Rust's text (`0.0000001`) |
| `--port 1e3`, `--port 0x10`, `ARENA_PORT=""`, `ARENA_HOST=""` | accepted (the empty host listens on all interfaces; the empty port is 0) | an error. Only a whole number from 0 to 65535 is a port |
| `replay --url https://...` | works | an error: the program has no TLS. The bridge is local and speaks plain HTTP |
| `--host ""` (an empty text) | listens on all interfaces | error "could not listen". An empty host is never what a person wants, and the bridge stays on `127.0.0.1` unless told otherwise |

Every other difference found in phase R-5 is a bug in the Rust code, or it is added to this table with a reason.

Places where JavaScript's loose typing shows, and which the port must copy for the cases that real payloads reach: `String(x)` on a value that is not a string (used in `describeTarget` and for the permission text), `??` on `null` and missing fields, `Boolean(response.error)`, a number in `session_id` (the event is then rejected by `validateEvent`, as today), and `arr[0]` on an empty array.

## Phases

Each phase ends with a pull request that passes CI. The effort numbers are a rough guess, in working days.

### R-0: spike and decision (0.5 day)

**Done (2026-11-21).** `axum` (with `tokio`) against `tiny_http` with `tungstenite`, each with one route to post events and one WebSocket route, release profile of decision 9:

| | Crates | Stripped binary (macOS arm64) | Notes |
|---|---|---|---|
| `axum` | 87 | 719 KB | threads for every connection, answers ping and close frames |
| `tiny_http` + `tungstenite` | 39 | 487 KB | one thread takes the requests, so one slow post blocks all; the WebSocket handshake and the ping and close frames would be our code |

The real bridge (the `axum` stack, all adapters) is 1.0 MB per Apple slice and 2.1 MB universal. Idle memory: 2.7 MB for the spike, against 55 MB for the Node bridge (Node 26, same machine). `axum` was chosen. The ADR criterion (numbers decide) is met. Not checked in R-0: the runners `ubuntu-24.04-arm` and `windows-11-arm`, and the Linux and Windows builds (this machine is a Mac).


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

**Done (2026-11-21).** The scripts of the differential check needed the Node bridge, so they were removed with it in R-7 (`git log` has the Node bridge; the scripts were not committed). What they did and found is under "What was checked".

* **Golden check.** The Rust tests convert every file in `schema/examples/` and compare with `godot/test/fixtures/*.events.jsonl` (made today by the Node adapters).
* **Differential check.** A script (`bridge-rs/tools/diff.mjs`) starts both bridges, posts the same payloads to both, and compares what a WebSocket client receives. Inputs: the corpora in `schema/examples/`, then the same payloads with a mutation each (a field dropped, a field set to `null`, a number, an empty string, an empty array, a very long string, a character outside the basic plane). Every difference is a Rust fix or a row in the table above. The script runs in CI until the cutover.
* **Godot tests.** Change `bridge-link.test.mjs`, `replay.test.mjs` and `cost.mjs` to start the binary (a built path from an environment variable, or `cargo build` first) instead of `createBridge` and `cli.js`. The restart test kills the process and starts it again on the same port. `example-events.mjs` and its test are replaced by `bridge-rs/examples/fixtures.rs`, which writes the fixtures (`cargo run --example fixtures`). A `cargo test` fails when `godot/test/fixtures/*.events.jsonl` are out of date. The Godot tests only read the fixtures.

### R-6: CI and release (1.5 days)

* `ci.yml`: a Rust job on three systems (Linux, macOS, Windows): `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`. A second job runs the adapter script tests. Dependabot gets a `cargo` entry; its alerts cover advisories. `cargo deny` is not used: it needs a third-party action or a long build, and the repository pins every action to a commit.
* `release.yml`: a matrix job builds the binary for the five platforms on native runners, runs `agent-workshop-bridge --help` and a short `serve` and `/health` check on each, and uploads the files. The macOS job builds both Apple targets and joins them with `lipo`. The release job downloads these files and the app archives.
* `package.mjs`: also makes the bridge archives. The names are `AgentWorkshopBridge-<version>-<os>-<arch>` with `.zip` (Windows and macOS) or `.tar.gz` (Linux), and `macos-universal` for macOS. Each archive holds one folder with the binary and `LICENSE` (the bridge is code, so no `LICENSE-ASSETS`). The Linux binary and the macOS binary keep the executable flag. `SHA256SUMS` lists the bridge archives too, and the attestation covers them. Update `package.test.mjs`.
* `docs/releasing.md`: add the bridge archives to the table of files.
* `version.mjs`: the version places change from `bridge/package.json` and `bridge/package-lock.json` to `bridge/Cargo.toml` and the `agent-workshop-bridge` entry of `Cargo.lock`. Update `version.test.mjs`.
* macOS: the binary is not signed or notarized, as the apps are not. A downloaded unsigned binary gets the quarantine flag, and Gatekeeper blocks it. Apple silicon needs at least an ad-hoc signature, so run `codesign --force --sign -` after `lipo`. The release notes tell the user how to open it. Windows shows SmartScreen. Both match what `docs/releasing.md` says about the apps.
* Make the first release after this a pre-release.

### R-7: cutover (0.5 day)

**Done (2026-11-21), except the step "after one pre-release was run on at least two platforms by hand", which needs a release.** The Node bridge is deleted (it stays in git history).

Do this after one pre-release was run on at least two platforms by hand.

* Delete `bridge/src/`, `bridge/test/`, `package.json` and `package-lock.json`. Move `bridge-rs/` to `bridge/`. Remove the Node bridge job and the differential script.
* Update every place that names the Node bridge: `README.md` and `README.pl.md` (the Polish translation is changed in the same step), `godot/README.md` (it names `example-events.mjs`, and tells the reader to run `npm ci` in `bridge/`), `docs/releasing.md`, the Pi `ingest` lines in `adapters/` and the root README, the test commands and rule 2 in `CLAUDE.md` (`bridge/src/schema.js` becomes `bridge/src/schema.rs`), and the `.github/dependabot.yml` npm entry. The plans in `docs/` that say "bridge (Node)" get a short note.
* Quick start becomes: download the bridge archive for your system, run `agent-workshop-bridge serve`, start the app. Building from source needs Rust (`cargo run -- serve`).

### R-8: the app starts the bridge (after R-7)

**Done (2026-11-21).** The launcher is `godot/src/net/bridge_launcher.gd`, the saved setting is `godot/src/net/bridge_settings.gd` (`user://settings.cfg`), the options are `--start-bridge[=<path>]` and `--no-start-bridge`, and the bridge has the flag `--exit-when-stdin-closes`. Checks: `godot/test/test_bridge_launcher.gd` and `godot/tools/launcher.test.mjs` (the real app, the real launcher and the real bridge: start, normal quit, kill of the app, a bridge that already runs, a taken port, a non-local address, a path that is not a file, no start without the option). The pipe start was checked on macOS only. No switch in the interface is needed (owner, 2026-11-21). **Still open:** the check on Windows and Linux (CI will run it), and macOS Gatekeeper with a downloaded bridge. See ADR 0014 for details, including the reader threads that the launcher needs.

The owner wants a setting in the Godot app that starts the bridge by itself. The rules are in ADR 0014 (proposed). It touches rule 3 (the bridge stays on `127.0.0.1`, stores nothing and broadcasts only schema fields). In short:

* **Where the app finds the bridge.** The archives are separate, so the app looks for the configured path, then `agent-workshop-bridge` next to the app, then on the `PATH`. It never downloads it.
* **Default.** Off, so the app never starts a program that the person did not choose. The command line wins over the saved setting.
* **When it starts.** Only for a local address, and only when `GET /health` gets no answer. If a bridge already runs, the app uses it.
* **Who stops it.** The app stops a bridge that it started, when it quits. It never stops one that it did not start. After a crash of the app the bridge ends too: it exits when its standard input closes, or when its parent process is gone. The bridge needs a flag for this (add it in phase R-4 or R-8).
* **Port clash and errors.** Show one short message with the first lines of the bridge's output, and keep the reconnect loop and the demo mode.
* **Checks first.** Whether the app has a saved setting and a place for it in the interface, how Godot's pipe start works on the three systems, and how macOS treats a downloaded unsigned bridge.
* **Code.** The process handling sits outside `art/` (rule 7). Test it with the real binary and the real client (the cases are in the ADR).

## What was checked (2026-11-21)

On one machine (macOS, Apple silicon, Rust 1.100, Node 26), against the Node bridge as it was in `main` before the port:

* **Tests.** 104 Rust tests (65 unit, 14 for the command line with the real binary, 22 for the server with real HTTP and WebSocket clients, 1 for the demo scenes, 2 for the Godot fixtures) and 3 Node tests of the adapter scripts (OpenCode plugin, Pi extension, Hermes hook script) against the real binary. `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` are clean.
* **Adapters, differential.** Both implementations got the same inputs: the example sessions, the same sessions with one value changed at a time (a field removed; set to `null`, numbers, texts, arrays, objects, long texts, texts from elsewhere in the corpus), every corpus through every adapter, canonical events through `POST /event`, and transcripts. 49,000 runs and 626,000 inputs for each of 5 random seeds: no differences, except those in the table above. A deliberate bug in the Rust code was found at once, so the check can fail.
* **Server, differential.** 2,147 requests (7 methods, 21 paths, 20 bodies, including 9 MB and over-limit bodies) and one WebSocket stream, to both servers: the same status, content type and body, after the fix of one real difference that this check found (an unknown framework must be a `404` before the body is read).
* **Godot.** `cd godot && npm test` passes against the Rust binary, with the launcher tests of R-8: 620 GUT tests and 187 of 188 Node tests (1 skipped: the art render, which needs Chromium). That includes the real client through a bridge restart, a late bridge, and a replayed Claude Code session. The Godot fixtures that the Rust code writes are byte for byte the ones that the Node code wrote.
* **macOS release build.** Both Apple targets built, joined with `lipo`, signed with `codesign --sign -`, and the universal file passed `tools/smoke.mjs` (2.1 MB). The Intel half could not be run here (no Rosetta).
* **An independent review** (a second reader that had the code and the Node source, not these notes) found, and the work fixed: nine `clippy` errors that would have failed CI (they appeared when `rust-version` was removed, after the first clippy run); a JSON text with a lone surrogate escape lost the whole event; a byte order mark hid the first line of a transcript; numbers in `target` were written as `5.0` instead of `5`; events of posts that arrive together could reach the clients out of the adapter's order; a client that stopped reading held up to 4,096 events for ever (now dropped after 10 s); `ingest --url` with no value ended the program; `replay` with a tiny `--speed` could panic; a launcher on `ws://[::1]` started a bridge on 127.0.0.1 that the client could not reach. The differential checks were run again after the fixes: no differences.
* **Other targets, compile only.** `cargo check --all-targets` passes for `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`, `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl` (no linking, nothing run).
* **Not checked:** the workflows (they were only parsed as YAML), running the tests on Linux and Windows, linking the musl static builds, Windows on ARM, and the Linux ARM runner. The first run of "Release" by hand will show these. The Polish README was changed by hand and not reviewed by a native speaker.

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

None for R-0 to R-7. The questions for R-8 are in its section. After R-7, one change is left for later: the adapters' session maps grow without a limit (decision 4 above).
