# Test fixtures

Some of these files are fixed snapshots. The JavaScript mockup made them at commit
`1e6531a128cdf339385c0ef5df27cf8d3d3eceab`. That is the last commit before the mockup was removed.
The mockup is in the git history, in `tools/mockup-2d/`. No tool makes these files again.
Do not edit them by hand.

| File | What it is |
|---|---|
| `arena_rules.json` | Results of the JavaScript arena rules: the pure functions, the arena model and the camera. |
| `rng.json` | The first 64 outputs of `mulberry32` for 14 seeds. |
| `camera-arenas.json`, `camera-many.json`, `camera-ten.json`, `camera-follow.json` | The camera input of each arena scene, and the log and frames of the JavaScript camera. |
| `scene-reference.json` | What the mockup decided for each arena scene: the arena of each agent and the camera log. |
| `art_variants.json` | The table of pictures that the art code makes. `node tools/render-art.mjs` writes it. It is not from the mockup. |
| `*.events.jsonl`, `expected-trace.json` | The example sessions as canonical events, and the expected visits. These are not from the mockup. `node tools/example-events.mjs` makes the events again. |

The first four rows come from the mockup. Each file with a `provenance` field names the commit
and the SHA-256 hash of each mockup source file. The hashes are those at that commit.

If a rule changes in the future, change `src/core/arena_rules.gd` and write the new expected
values by hand, with a comment that says why. Do not try to run the old JavaScript again.
