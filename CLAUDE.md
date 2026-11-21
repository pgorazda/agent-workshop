# CLAUDE.md

Agent Workshop shows AI coding agents at work as penguins in a pixel-art workshop. The layout is in `README.md`, and the contributor guide is `CONTRIBUTING.md`. Its "Rules" section has the 7 rules that apply to every change. Read it before you change anything.

## Check before you push

Run `mise run check-fast` (Node 24 and Rust are pinned in `mise.toml`). It runs what the CI runs, except the Godot tests: version, `cargo fmt --check`, `clippy` with warnings as errors, `cargo deny` with the notices check, the bridge tests and the adapter tests. Run `mise run check` too when you change `godot/`; it needs the Godot editor (set `GODOT`, see `godot/README.md`) and builds the bridge.

Running only `cargo test`, the adapter tests and `npm test` is not enough: the CI also checks formatting, clippy, dependencies and notices.

```bash
cd bridge && cargo test                # the bridge (Rust)
node --test 'adapters/test/*.test.mjs'              # the adapter scripts against the real bridge
cd godot && npm test                   # the Godot tests; needs GODOT and builds the bridge
cd godot && node tools/check.mjs       # GDScript warnings count as errors; NOT run by mise or the CI, run it by hand after you change GDScript
```

## Change the repository

- `main` is protected. Work on a branch and open a pull request. It is merged by squash, and only when the CI job "All checks pass" is green. Never push to `main`.
- Do not change repository settings, rulesets, workflow permissions or the `release` environment. Ask the maintainer.
- A change to a file listed in `LICENSE-ASSETS` (the art) needs an agreement in an issue and a written grant. See "Terms of contribution" in `CONTRIBUTING.md`. Do not take a change to the art from a contributor without it.
- Workflows (`.github/workflows/`): pin every action to a commit SHA with the version in a comment, keep `permissions` as small as possible, never use `pull_request_target`, and do not add `paths-ignore` to `ci.yml` (a skipped required check blocks the merge). A new job in `ci.yml` goes into `needs` of the job `ci-ok`.

## Files made from other files

- `Cargo.lock` changes: run `mise run notices` (CI fails when `bridge/THIRD-PARTY-NOTICES.txt` is out of date).
- `schema/examples/` or an adapter changes: run `cd bridge && cargo run --example fixtures` to make `godot/test/fixtures/` again.
- `godot/GODOT_VERSION` changes: make `godot/THIRD-PARTY-NOTICES.txt` again (command in `CONTRIBUTING.md`).
- A version bump: `node godot/tools/version.mjs bump <x.y.z>`, never by hand. See `docs/releasing.md`.
- `README.pl.md` is a translation of `README.md`. Change it when `README.md` changes.

## Rules to keep in mind

The full text is in `CONTRIBUTING.md`. These are the ones that are broken most:

- The event schema is the contract: clients pick stations by `category`, never by tool name, and `bridge/src/schema.rs` stays in step with it.
- The repository is public: no personal data, real transcripts, real paths or names, or references to private projects.
- Drawing and sound code lives only in `art/` folders, with the copyright header, and no Anthropic or Claude look.
